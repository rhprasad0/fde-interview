"""Spec 05 step 4: the eval harness, local and direct-MCP.

  eval_harness.py [--stub] [--dry-run] [--runs 3]   run the questions file, write workforce.eval.runs
  eval_harness.py load-session <trace.jsonl> [--dry-run]   tester session as run_index = 0 rows, upload trace

Writes as Ryan's user (databricks auth token -p workforce) through the Statement Execution API.
--dry-run prints each redacted statement and its parameters instead of sending it.
"""

import argparse
import hashlib
import json
import re
import subprocess
import sys
import time
import uuid
from datetime import datetime, timezone
from pathlib import Path

import anthropic
import httpx
import yaml

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "prototype"))
import agent as A  # noqa: E402

QUESTIONS = A.REPO / "challenge/eval/questions.yaml"
JUDGE_PROMPT = A.REPO / "challenge/eval/judge-prompt.md"
JUDGE_MODEL = "claude-sonnet-5-5"
STUB, DRY = False, False
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
    """exact for counts; abs:x and pp:x both mean |a - b| <= x in the truth's own units."""
    try:
        return a == b if tol in (None, "exact") else abs(float(a) - float(b)) <= float(tol.split(":")[1])
    except (TypeError, ValueError):
        return False


def _pairs(v):
    if isinstance(v, dict):
        return [(str(k).strip().upper(), x, None) for k, x in v.items()]
    return [(str(i.get("key")).strip().upper(), i.get("value"), i.get("rank")) for i in v or [] if isinstance(i, dict)]


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
    ok = not q.get("requires_imputed_label") or any(w in t for w in ("estimated", "imputed", "approximate"))
    return ok and (not q.get("requires_synthetic_label") or any(w in t for w in ("synthetic", "generated", "demo")))


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


def clarify(q, row):
    t = (row["answer_text"] or "").rstrip()
    return row["answer_value"] is None and t.endswith("?") and sum(_has(t, r) for r in _phrases(q.get("acceptable_readings"))) >= 2


def faithfulness(q, row):
    return row.get("_verdict") == "pass"


def assumption_labeled(q, row):
    return _has(row["answer_text"], q.get("assumption_text")) and (
        list_match(q, row) if isinstance(q.get("truth_value"), list) else numeric_match(q, row))


SCORERS = [  # table order: failure_category is the first that fails
    (numeric_match, lambda q: q["expected_behavior"] == "number"),
    (list_match, lambda q: q["expected_behavior"] == "list"),
    (labels_present, lambda q: q["tier"] in ("verified", "genie")),
    (tool_use, lambda q: q["tier"] == "verified"),
    (provenance, lambda q: True),
    (genie_sql_stored, lambda q: q["tier"] == "genie"),
    (refusal, lambda q: q["class"] == "refusal"),
    (data_limit, lambda q: q["class"] == "data_limit"),
    (clarify, lambda q: q["class"] == "clarify"),
    (faithfulness, lambda q: q["expected_behavior"] == "narrative"),
    (assumption_labeled, lambda q: q["class"] == "context_supplied"),
]


def judge(q, row):
    """Narrative faithfulness. Contract with judge-prompt.md: the reply's first word is PASS or FAIL."""
    if not JUDGE_PROMPT.exists():
        return "fail", "no judge prompt: challenge/eval/judge-prompt.md does not exist yet (spec 04 step 6)"
    msg = anthropic.Anthropic(api_key=A.ENV["ANTHROPIC_API_KEY"]).messages.create(
        model=JUDGE_MODEL, max_tokens=16000, system=JUDGE_PROMPT.read_text(),
        messages=[{"role": "user", "content": json.dumps({"question": q["verbatim"], "truth_facts": q.get("truth_facts"),
                                                          "must_not_claim": q.get("must_not_claim"), "answer_text": row["answer_text"]})}])
    text = "".join(b.text for b in msg.content if b.type == "text").strip()
    return ("pass" if text.upper().startswith("PASS") else "fail"), text


# ---- rows ----

STRUCT = "ARRAY<STRUCT<name STRING, params STRING, result_rows BIGINT, imputed_rows BIGINT, synthetic_rows BIGINT, duration_ms BIGINT>>"
TYPES = {"run_index": "INT", "run_at": "TIMESTAMP", "latency_ms": "BIGINT", "cost_usd": "DOUBLE", "input_tokens": "BIGINT",
         "output_tokens": "BIGINT", "pass": "BOOLEAN", **{f.__name__: "BOOLEAN" for f, _ in SCORERS}}
COLS = ["set_version", "id", "run_index", "session_id", "run_at", "agent_git_sha", "prompt_hash", "model_id", "provider_served",
        "question_text", "turn_1_answer_text", "answer_text", "answer_value", "cited_tools", "tool_calls", "genie_sql",
        "genie_statement_id", "latency_ms", "cost_usd", "input_tokens", "output_tokens", "error",
        *[f.__name__ for f, _ in SCORERS], "pass", "failure_category"]


def build_row(q, run_index, lines):
    """One eval.runs row from a question's trace lines; two-turn rows are graded on the last line."""
    last = lines[-1]
    row = {k: last.get(k) for k in COLS if k in last}
    row.update(set_version=q.get("set_version") or A.SET_VERSION, id=q["id"], run_index=run_index, run_at=last["ts"])
    # Both turns' calls: the second answer may cite a function the first turn ran (provenance).
    row["tool_calls"] = [{k: c.get(k) for k in ("name", "params", "result_rows", "imputed_rows", "synthetic_rows", "duration_ms")}
                         for line in lines for c in line["tool_calls"]]
    for k in ("latency_ms", "cost_usd", "input_tokens", "output_tokens"):
        row[k] = sum(line.get(k) or 0 for line in lines)
    row["error"] = last["error"] or next((x["error"] for x in lines[:-1] if x["error"] not in (None, "format")), None)
    if q["expected_behavior"] == "narrative" and not STUB:
        row["_verdict"], row["_rationale"] = judge(q, row)
    failed = None
    for f, applies in SCORERS:
        row[f.__name__] = f(q, row) if applies(q) else None
        if row[f.__name__] is False and failed is None:
            failed = f.__name__
    row["pass"] = row["error"] is None and failed is None
    row["failure_category"] = "error" if row["error"] else failed
    return row


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
    exprs, params = [], []
    for c in COLS:
        v = row.get(c)
        if c == "tool_calls":
            exprs.append(f"from_json(:{c}, '{STRUCT}')")
            v = json.dumps([{**t, "params": json.dumps(t["params"])} for t in v])
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


def run(set_version, runs=3):
    y, qs = _questions()
    if y["set_version"] != set_version:
        raise SystemExit(f"questions file is {y['set_version']}, asked for {set_version}")
    if not qs and STUB:  # the file is empty until the session; the dry run still writes one row
        qs = {"STUB": {"id": "STUB", "set_version": set_version, "verbatim": "stub dry run", "class": "refusal",
                       "expected_behavior": "refusal", "tier": "refusal", "must_offer": "stub"}}
        runs = 1
    print(f"{len(qs)} questions x {runs} runs, prompt {A.PROMPT_HASH[:12]}")
    for q in qs.values():
        for r in range(1, runs + 1):
            sid = f"{q['id']}-r{r}-{uuid.uuid4().hex[:6]}"
            if not STUB:
                _agents[sid] = A.build_agent(sid, run_index=r)
            if q["class"] == "context_supplied":
                lines = [invoke(q["turn_1"], sid, q_id=q["id"]), invoke(q["turn_2"], sid, context=q["supplied_context"], q_id=q["id"])]
            else:
                lines = [invoke(q["verbatim"], sid, q_id=q["id"])]
            if sid in _agents:
                _agents.pop(sid).cleanup()
            row = build_row(q, r, lines)
            print(f"{q['id']} run {r}: pass={row['pass']} failure={row['failure_category']} {row['latency_ms']}ms")
            write_row(row)


def load_session(trace_path):
    _, qs = _questions()
    path, prev, n = Path(trace_path), None, 0
    for text in path.read_text().splitlines():
        line = json.loads(text)
        q = qs.get(line["q_id"])
        if q:
            row = build_row(q, 0, [prev, line] if line.get("supplied_context") and prev else [line])
            write_row(row)
            n += 1
        prev = line
    print(f"{n} session rows from {path.name}")
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
    ap.add_argument("--runs", type=int, default=3)
    ap.add_argument("--set-version", default=A.SET_VERSION)
    a = ap.parse_args()
    STUB, DRY = a.stub, a.dry_run
    if a.cmd == "load-session":
        load_session(a.trace)
    else:
        run(a.set_version, a.runs)
