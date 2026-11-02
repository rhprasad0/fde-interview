"""Spec 05 step 4, ported to Strands Evals by spec 04 (2026-11-02): the eval harness, local and direct-MCP.

  eval_harness.py [--stub] [--runs 3] [--workers 16] [--delta [--dry-run]]   run the questions file
  eval_harness.py load-session <trace.jsonl> [--delta [--dry-run]]           tester session as run_index = 0 rows

Every row is appended to challenge/eval/experiments.jsonl, the record of results. --delta also writes
workforce.eval.runs and eval.judge as Ryan's user through the Statement Execution API (deferred 2026-11-02:
the tables need 04_eval.sql), and uploads a session trace; --dry-run prints those statements instead.
Each question is a Strands Evals Case, each scorer an Evaluator; one Experiment is one run. pass^3 and
failure_category are computed here, in scorer-table order, because Strands gathers evaluators concurrently.
"""

import argparse
import asyncio
import hashlib
import json
import re
import subprocess
import sys
import time
import uuid
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone
from pathlib import Path

import httpx
import yaml
from strands.models.openai_responses import OpenAIResponsesModel  # Luna refuses function tools on chat completions
from strands_evals import Case, Experiment
from strands_evals.evaluators import Evaluator, OutputEvaluator
from strands_evals.types import EvaluationData, EvaluationOutput
from strands_evals.types.evaluation import NOT_APPLICABLE

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "prototype"))
import agent as A  # noqa: E402

QUESTIONS = A.REPO / "challenge/eval/questions.yaml"
JUDGE_PROMPT = A.REPO / "challenge/eval/judge-prompt.md"
JUDGE_MODEL = "gpt-6-luna"  # a different vendor from the Claude agent; also the agent's fallback (judge_same_family)
EXPERIMENTS = A.REPO / "challenge/eval/experiments.jsonl"  # every row written, for hill-climbing analysis
EXPERIMENT_ID = None
STUB, DRY, DELTA = False, False, False
WORKERS = 16  # agent runs and scoring in parallel; Genie questions are rate-limited in agent.py
_agents = {}


def invoke(question, session_id, context=None, q_id=None):
    """The spec 04 interface. Returns the trace line, a superset of the interface dict."""
    if STUB:
        return {"ts": datetime.now(timezone.utc).isoformat(timespec="seconds"), "session_id": session_id,
                "agent_git_sha": A.GIT_SHA, "prompt_hash": A.PROMPT_HASH, "model_id": A.MODEL_ID,
                "provider_served": None, "question_text": question, "turn_1_answer_text": None,
                "answer_text": "no answer", "answer_value": None, "cited_tools": [], "tool_calls": [],
                "genie_sql": None, "genie_statement_id": None, "latency_ms": 0, "input_tokens": 0,
                "output_tokens": 0, "cost_usd": 0.0, "error": None}
    if session_id not in _agents:
        _agents[session_id] = A.build_agent(session_id)
    return A.run_turn(_agents[session_id], question, q_id=q_id, context=context)


# ---- scorers: spec 04 step 6, each returns pass (True) or fail (False) ----

def _phrases(x):
    return [p for p in (x if isinstance(x, list) else [x]) if p]


def _has(text, x):
    return any(str(p).lower() in (text or "").lower() for p in _phrases(x))


def _close(a, b, tol):
    """exact for counts; abs:x and pp:x both mean |a - b| <= x in the truth's own units; pct:x is x percent of truth."""
    try:
        if tol in (None, "exact"):
            return a == b
        kind, x = tol.split(":")
        bound = abs(float(b)) * float(x) / 100 if kind == "pct" else float(x)
        return abs(float(a) - float(b)) <= bound
    except (TypeError, ValueError):
        return False


def _pairs(v):
    if isinstance(v, dict):
        return [(str(k).strip().upper(), x, None) for k, x in v.items()]
    return [(str(i.get("key")).strip().upper(), i.get("value"), i.get("rank")) for i in v or [] if isinstance(i, dict)]


LABELS = ("Verified", "Exploratory", "Not available")
WANT_LABEL = {"verified": "Verified", "genie": "Exploratory", "refusal": "Not available"}


def _label(text):
    first = (text or "").strip().splitlines()[0].strip() if (text or "").strip() else ""
    return first if first in LABELS else None


def label_match(q, row):
    return row["label"] == WANT_LABEL[q["tier"]]


def numeric_match(q, row):
    return _close(row["answer_value"], q["truth_value"], q.get("tolerance"))


def list_match(q, row):
    got, want = _pairs(row["answer_value"]), _pairs(q["truth_value"])
    if any(r is not None for _, _, r in want):  # a ranking: order matters
        return len(got) == len(want) and all(g[0] == w[0] and _close(g[1], w[1], q.get("tolerance")) for g, w in zip(got, want))
    g = {k: v for k, v, _ in got}
    return set(g) == {k for k, _, _ in want} and all(_close(g[k], v, q.get("tolerance")) for k, v, _ in want)


def labels_present(q, row):
    t = (row["answer_text"] or "").lower()
    return not q.get("requires_imputed_label") or any(w in t for w in ("estimated", "imputed", "approximate"))


def tool_use(q, row):
    names = {c["name"] for c in row["tool_calls"]}
    return set(q.get("expected_tools") or []) <= names and not any("sql" in n for n in names)


def provenance(q, row):
    names = {c["name"] for c in row["tool_calls"]}
    return all(t in names or (t == "genie" and row["genie_sql"]) for t in row["cited_tools"])


def genie_sql_stored(q, row):
    sid = row["genie_statement_id"]
    if not (row["genie_sql"] and sid):
        return False
    if not re.fullmatch(r"[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}", sid):
        return True  # spec 04 fallback: no statement id, the Genie message id is stored
    res = _sql("SELECT count(*) FROM system.query.history WHERE statement_id = :sid", [{"name": "sid", "value": sid}])
    return bool(res) and int(res["result"]["data_array"][0][0]) > 0


def refusal(q, row):
    return (not any(c["result_rows"] for c in row["tool_calls"]) and row["answer_value"] is None
            and _has(row["answer_text"], q.get("must_offer")))


def data_limit(q, row):
    return row["answer_value"] is None and _has(row["answer_text"], q.get("limit_text")) and _has(row["answer_text"], q.get("nearest"))


def reading_stated(q, row):
    """Truth for the first reading, and the last sentence names that reading and one alternative."""
    first, *alts = q.get("acceptable_readings") or [None]
    sentences = [x for x in re.split(r"(?<=[.!?])\s+", (row["answer_text"] or "").strip()) if x.strip()]
    last = sentences[-1] if sentences else ""
    value_ok = list_match(q, row) if isinstance(q.get("truth_value"), list) else numeric_match(q, row)
    return value_ok and _has(last, first) and any(_has(last, a) for a in alts)


def faithfulness(q, row):
    """Placeholder for the table slot; the Judge evaluator below is what scores it."""
    raise NotImplementedError


def assumption_labeled(q, row):
    return _has(row["answer_text"], q.get("assumption_text")) and (
        list_match(q, row) if isinstance(q.get("truth_value"), list) else numeric_match(q, row))


SCORERS = [  # table order: failure_category is the first that fails
    (label_match, lambda q: True),
    (numeric_match, lambda q: q["expected_behavior"] == "number"),
    (list_match, lambda q: q["expected_behavior"] == "list"),
    (labels_present, lambda q: q["tier"] in ("verified", "genie")),
    (tool_use, lambda q: q["tier"] == "verified"),
    (provenance, lambda q: True),
    (genie_sql_stored, lambda q: q["tier"] == "genie"),
    (refusal, lambda q: q["class"] == "refusal"),
    (data_limit, lambda q: q["class"] == "data_limit"),
    (reading_stated, lambda q: q["class"] == "reading_stated"),
    (faithfulness, lambda q: q["expected_behavior"] == "narrative"),
    (assumption_labeled, lambda q: q["class"] == "context_supplied"),
]


def _verdict(ok, label=None, reason=None):
    return [EvaluationOutput(score=float(ok), test_pass=ok, label=label or ("pass" if ok else "fail"), reason=reason)]


NA = [EvaluationOutput(score=1.0, test_pass=True, label=NOT_APPLICABLE)]


class Rule(Evaluator):
    """One code scorer from SCORERS. actual_output is the row; the question rides in case metadata."""

    def __init__(self, fn, applies):
        super().__init__(name=fn.__name__)
        self.fn, self.applies = fn, applies

    def evaluate(self, data):
        q = data.metadata["q"]
        return _verdict(bool(self.fn(q, data.actual_output))) if self.applies(q) else NA


class Judge(OutputEvaluator):
    """Narrative faithfulness on gpt-6-luna. The judge sees the answer text and the truth facts, not the row."""

    def __init__(self, applies):
        model = None if STUB else OpenAIResponsesModel(client_args={"api_key": A.ENV["OPENAI_API_KEY"]}, model_id=JUDGE_MODEL)
        super().__init__(rubric=JUDGE_PROMPT.read_text() if JUDGE_PROMPT.exists() else "", model=model, name="faithfulness")
        self.applies = applies

    def _prep(self, data):
        """(early result, None) when there is nothing to call the model for; else (None, data rewrapped for the judge)."""
        q, row = data.metadata["q"], data.actual_output
        if not self.applies(q):
            return NA, None
        if STUB:
            return _verdict(False, reason="stub run: judge not called"), None
        if not JUDGE_PROMPT.exists():
            return _verdict(False, reason="no judge prompt: challenge/eval/judge-prompt.md is missing"), None
        if not q.get("truth_facts"):  # nothing to be faithful to; raising makes the row an error, like a missing truth_value
            raise ValueError("no truth_facts on this narrative row (spec 04 step 3)")
        return None, EvaluationData(input=q.get("turn_2") or q["verbatim"], actual_output=row["answer_text"] or "",
                                    expected_output=json.dumps({"truth_facts": q.get("truth_facts"),
                                                                "must_not_claim": q.get("must_not_claim")}),
                                    name=data.name, metadata=data.metadata)

    def evaluate(self, data):
        early, judged = self._prep(data)
        return early if early is not None else super().evaluate(judged)

    async def evaluate_async(self, data):  # OutputEvaluator overrides this path separately; Experiment calls it
        early, judged = self._prep(data)
        return early if early is not None else await super().evaluate_async(judged)


def _evaluators():
    return [Judge(applies) if f is faithfulness else Rule(f, applies) for f, applies in SCORERS]


# ---- rows ----

TOOL_KEYS = ("name", "params", "result_rows", "imputed_rows", "synthetic_rows", "duration_ms", "result_values")
STRUCT = ("ARRAY<STRUCT<name STRING, params STRING, result_rows BIGINT, imputed_rows BIGINT, synthetic_rows BIGINT, "
          "duration_ms BIGINT, result_values STRING>>")
TYPES = {"run_index": "INT", "run_at": "TIMESTAMP", "latency_ms": "BIGINT", "cost_usd": "DOUBLE", "input_tokens": "BIGINT",
         "output_tokens": "BIGINT", "tool_call_count": "BIGINT", "judge_same_family": "BOOLEAN", "pass": "BOOLEAN",
         **{f.__name__: "BOOLEAN" for f, _ in SCORERS}}
COLS = ["set_version", "id", "run_index", "session_id", "run_at", "agent_git_sha", "prompt_hash", "model_id", "provider_served",
        "question_text", "turn_1_answer_text", "answer_text", "answer_value", "cited_tools", "tool_calls", "genie_sql",
        "genie_statement_id", "label", "tool_call_count", "judge_same_family", "latency_ms", "cost_usd", "input_tokens",
        "output_tokens", "error",
        *[f.__name__ for f, _ in SCORERS], "pass", "failure_category"]


def build_row(q, run_index, lines):
    """One unscored eval.runs row from a question's trace lines; multi-turn rows are graded on the last line."""
    last = lines[-1]
    row = {k: last.get(k) for k in COLS if k in last}
    row.update(set_version=q.get("set_version") or A.SET_VERSION, id=q["id"], run_index=run_index, run_at=last.get("ts"))
    # Every turn's calls: a later answer may cite a function an earlier turn of the same run ran (provenance).
    row["tool_calls"] = [{k: c.get(k) for k in TOOL_KEYS} for line in lines for c in line["tool_calls"]]
    for k in ("latency_ms", "cost_usd", "input_tokens", "output_tokens"):
        row[k] = sum(line.get(k) or 0 for line in lines)
    row["error"] = last.get("error") or next((x["error"] for x in lines[:-1] if x.get("error") not in (None, "format")), None)
    row["label"] = _label(row.get("answer_text"))
    row["tool_call_count"] = len(row["tool_calls"])
    narrative = q["expected_behavior"] == "narrative"
    row["judge_same_family"] = (row.get("provider_served") not in (None, "anthropic")) if narrative else None
    return row


def score(pairs):
    """pairs: [(q, row)]. Runs one Strands Experiment over the built rows and writes the verdicts onto them."""
    if not pairs:
        return []
    cases = [Case(name=f"{q['id']}#{i}", input=q.get("turn_2") or q["verbatim"], metadata={"q": q}) for i, (q, _) in enumerate(pairs)]
    rows = {c.name: row for c, (_, row) in zip(cases, pairs)}
    experiment = Experiment(cases=cases, evaluators=_evaluators())
    report = asyncio.run(experiment.run_evaluations_async(lambda case: {"output": rows[case.name]}, max_workers=WORKERS))
    got = {(c["name"], c["evaluator"]): (ok, outs, why) for c, ok, outs, why in
           zip(report.cases, report.test_passes, report.detailed_results, report.reasons)}
    for (q, row), c in zip(pairs, cases):
        failed = None
        for f, _ in SCORERS:
            ok, outs, why = got[(c.name, f.__name__)]
            if outs and all(o.label == NOT_APPLICABLE for o in outs):
                row[f.__name__] = None
                continue
            row[f.__name__] = bool(ok) and bool(outs)
            if not outs:  # the evaluator itself raised (a judge outage, a failed query): an error, not a verdict
                row["error"] = row["error"] or f"{f.__name__}: {A.redact(str(why))[:300]}"
            if f is faithfulness:
                row["_verdict"], row["_rationale"] = ("pass" if row[f.__name__] else "fail"), (outs[0].reason if outs else why)
            if row[f.__name__] is False and failed is None:
                failed = f.__name__
        if failed == "label_match" and row["label"] == "Not available" and q["expected_behavior"] in ("number", "list", "narrative"):
            failed = "false_not_available"
        row["pass"] = row["error"] is None and failed is None
        row["failure_category"] = "error" if row["error"] else failed
    return [row for _, row in pairs]


def summary(rows, qs):
    """One line per tier: pass^1 is the mean run pass rate, pass^3 the share of questions passing every run."""
    by = {}
    for r in rows:
        by.setdefault(qs[r["id"]]["tier"], {}).setdefault(r["id"], []).append(r["pass"])
    for tier, per_q in sorted(by.items()):
        runs = [p for ps in per_q.values() for p in ps]
        print(f"{tier}: pass^1 {sum(runs)}/{len(runs)}  pass^k {sum(all(ps) for ps in per_q.values())}/{len(per_q)} questions")


def _sql(statement, params):
    if DRY:
        print(A.redact(statement))
        print("  params:", A.redact(json.dumps(params))[:2000])
        return None
    tok = json.loads(subprocess.run(["databricks", "auth", "token", "-p", "workforce"], capture_output=True, text=True,
                                    check=True).stdout)["access_token"]
    h = {"Authorization": f"Bearer {tok}"}
    r = httpx.post(f"{A.HOST}/api/2.0/sql/statements", headers=h, timeout=70, json={
        "warehouse_id": A.ENV["DATABRICKS_WAREHOUSE_ID"], "statement": statement, "parameters": params, "wait_timeout": "50s"})
    r.raise_for_status()
    body = r.json()
    while body["status"]["state"] in ("PENDING", "RUNNING"):
        time.sleep(5)
        body = httpx.get(f"{A.HOST}/api/2.0/sql/statements/{body['statement_id']}", headers=h, timeout=30).json()
    if body["status"]["state"] != "SUCCEEDED":
        raise RuntimeError(A.redact(json.dumps(body["status"])[:1000]))
    return body


def _param(name, v, typ="STRING"):
    p = {"name": name, "type": typ}
    if v is not None:
        p["value"] = str(v).lower() if isinstance(v, bool) else str(v)
    return p


def write_row(row):
    if not (STUB or DRY):  # local copy first, so a failed insert loses nothing
        with EXPERIMENTS.open("a") as f:
            f.write(json.dumps({"experiment_id": EXPERIMENT_ID, **row}, default=str) + "\n")
    if not DELTA:
        return
    exprs, params = [], []
    for c in COLS:
        v = row.get(c)
        if c == "tool_calls":
            exprs.append(f"from_json(:{c}, '{STRUCT}')")
            v = json.dumps([{**t, "params": json.dumps(t["params"]), "result_values": json.dumps(t.get("result_values"))} for t in v])
        elif c == "cited_tools":
            exprs.append(f"from_json(:{c}, 'ARRAY<STRING>')")
            v = json.dumps(v)
        elif c == "answer_value":
            exprs.append(f":{c}")  # JSON text: a number or a key-value list
            v = None if v is None else json.dumps(v)
        else:
            exprs.append(f":{c}")
        params.append(_param(c, v, TYPES.get(c, "STRING")))
    _sql(f"INSERT INTO workforce.eval.runs (`{'`, `'.join(COLS)}`) VALUES ({', '.join(exprs)})", params)
    if "_verdict" in row:
        jp = hashlib.sha256(JUDGE_PROMPT.read_bytes()).hexdigest()[:12] if JUDGE_PROMPT.exists() else None
        vals = {"set_version": row["set_version"], "id": row["id"], "run_index": row["run_index"], "judge_model": JUDGE_MODEL,
                "judge_prompt_version": jp, "verdict": row["_verdict"], "rationale": row["_rationale"]}
        _sql(f"INSERT INTO workforce.eval.judge ({', '.join(vals)}) VALUES ({', '.join(':' + k for k in vals)})",
             [_param(k, v, "INT" if k == "run_index" else "STRING") for k, v in vals.items()])


def _questions():
    y = yaml.safe_load(QUESTIONS.read_text())
    return y, {q["id"]: {**q, "set_version": y["set_version"]} for q in y.get("questions") or []}


def _turns(q, sid):
    """Every turn of one fresh run; the last line is the one graded."""
    if q["class"] == "context_supplied":
        return [invoke(q["turn_1"], sid, q_id=q["id"]), invoke(q["turn_2"], sid, context=q["supplied_context"], q_id=q["id"])]
    return [invoke(t, sid, q_id=q["id"]) for t in [*(q.get("prior_turns") or []), q["verbatim"]]]


def run(set_version, runs=3):
    global EXPERIMENT_ID
    EXPERIMENT_ID = f"{datetime.now(timezone.utc):%Y%m%dT%H%M%SZ}-{A.PROMPT_HASH[:8]}"
    y, qs = _questions()
    if y["set_version"] != set_version:
        raise SystemExit(f"questions file is {y['set_version']}, asked for {set_version}")
    if not qs and STUB:  # an empty file still exercises one row in the dry run
        qs = {"STUB": {"id": "STUB", "set_version": set_version, "verbatim": "stub dry run", "class": "refusal",
                       "expected_behavior": "refusal", "tier": "refusal", "must_offer": "stub"}}
        runs = 1
    print(f"{len(qs)} questions x {runs} runs on {WORKERS} workers, prompt {A.PROMPT_HASH[:12]}, experiment {EXPERIMENT_ID}")

    def one(job):  # one fresh agent per (question, run); nothing cached across runs
        q, r = job
        sid = f"{q['id']}-r{r}-{uuid.uuid4().hex[:6]}"
        try:
            if not STUB:
                _agents[sid] = A.build_agent(sid, run_index=r)
            lines = _turns(q, sid)
        except Exception as e:  # noqa: BLE001  (a crashed turn is an error row, never a retry)
            lines = [{"tool_calls": [], "error": f"{type(e).__name__}: {A.redact(str(e))[:300]}", "session_id": sid}]
        finally:
            if sid in _agents:
                _agents.pop(sid).cleanup()
        return q, build_row(q, r, lines)

    jobs = [(q, r) for r in range(1, runs + 1) for q in qs.values()]
    with ThreadPoolExecutor(max_workers=WORKERS) as pool:
        pairs = list(pool.map(one, jobs))
    every = score(pairs)
    for row in every:
        print(f"{row['id']} run {row['run_index']}: pass={row['pass']} failure={row['failure_category']} {row['latency_ms']}ms")
        write_row(row)
    summary(every, qs)


def load_session(trace_path):
    global EXPERIMENT_ID
    _, qs = _questions()
    path, prev, n, seen, pairs = Path(trace_path), None, 0, [], []
    EXPERIMENT_ID = f"session-{path.parent.name}"
    for text in path.read_text().splitlines():
        line = json.loads(text)
        q = qs.get(line["q_id"])
        if q:
            lines = [prev, line] if line.get("supplied_context") and prev else [line]
            # Run 0 is the whole session: a later answer may cite a call an earlier turn made (A05 cites A03's).
            earlier = {"tool_calls": [c for x in seen if x is not prev or len(lines) == 1 for c in x["tool_calls"]], "error": None}
            pairs.append((q, build_row(q, 0, [earlier, *lines])))
        seen.append(line)
        prev = line
    for row in score(pairs):
        write_row(row)
        n += 1
    print(f"{n} session rows from {path.name}")
    if not DELTA:
        return
    url = f"{A.HOST}/api/2.0/fs/files/Volumes/workforce/bronze/landing/eval/{path.name}?overwrite=true"
    if DRY:
        print("upload:", A.redact(url))
        return
    tok = json.loads(subprocess.run(["databricks", "auth", "token", "-p", "workforce"], capture_output=True, text=True,
                                    check=True).stdout)["access_token"]
    httpx.put(url, headers={"Authorization": f"Bearer {tok}"}, content=path.read_bytes(), timeout=60).raise_for_status()


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("cmd", nargs="?", choices=["run", "load-session"], default="run")
    ap.add_argument("trace", nargs="?")
    ap.add_argument("--stub", action="store_true")
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--delta", action="store_true", help="also write eval.runs and eval.judge (needs 04_eval.sql)")
    ap.add_argument("--runs", type=int, default=3)
    ap.add_argument("--workers", type=int, default=WORKERS)
    ap.add_argument("--set-version", default=A.SET_VERSION)
    a = ap.parse_args()
    STUB, DRY, WORKERS, DELTA = a.stub, a.dry_run, a.workers, a.delta
    if a.cmd == "load-session":
        load_session(a.trace)
    else:
        run(a.set_version, a.runs)
