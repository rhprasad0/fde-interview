"""Spec 06: the prototype agent, its Postgres tools, and the trace writer.

build_agent(session_id) -> Agent; run_turn(agent, text, q_id=None, context=None) -> trace line dict.
Reads challenge/.env itself; never prints or writes a host, secret, or password (see redact).
"""

import hashlib
import json
import os
import re
import shutil
import subprocess
import threading
import time
from datetime import date, datetime, timezone
from decimal import Decimal
from pathlib import Path

import anthropic
import psycopg
import yaml
from strands import Agent, tool
from strands.hooks import AfterToolCallEvent, BeforeToolCallEvent
from strands.models.anthropic import AnthropicModel
from strands.models.model import CacheConfig
from strands.telemetry import StrandsTelemetry
from strands.tools import PythonAgentTool
from strands.tools.executors import SequentialToolExecutor
from strands.types.exceptions import ContextWindowOverflowException, MaxTokensReachedException, ModelThrottledException

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[1]
RAW = Path(os.environ.get("RAW_DIR", REPO / "raw"))  # Lambda writes only under /tmp; a worktree points at the main raw/

ENV = dict(os.environ)  # the file overrides the environment locally; on Lambda there is no file
_envf = REPO / "challenge/.env"
for _line in _envf.read_text().splitlines() if _envf.exists() else []:
    _k, _sep, _v = _line.split("#", 1)[0].partition("=")
    if _sep:
        ENV[_k.strip()] = _v.strip().strip("'\"")

MODEL_ID = "claude-haiku-5-5"
EFFORT = "xhigh"  # Ryan, 2026-11-03, chosen on the held-out sweep (DECISIONS.md); read when an agent is built, so the harness --effort can set it first
MAX_TOKENS = 64000  # was 16000 until 2026-11-03; thinking counts against it, and the xhigh sweep truncated 12 of 40 runs
PRICE = {"inputTokens": 0.10, "outputTokens": 0.50, "cacheReadInputTokens": 0.01, "cacheWriteInputTokens": 0.125}  # $/MTok; cache read 0.1x, 5-min write 1.25x

_SECRETS = {ENV.get(k, ""): f"<{k.lower()}>" for k in ("PGHOST", "PGPASSWORD", "AGENT_PGPASSWORD", "ANTHROPIC_API_KEY")}


def redact(s: str) -> str:
    for v, p in sorted(_SECRETS.items(), key=lambda kv: -len(kv[0])):
        if v:
            s = s.replace(v, p)
    return s


_files = [HERE / "prompt.md", *sorted((HERE / "skills").glob("*.md"))]
SYSTEM = "\n\n".join(f.read_text() for f in _files)
PROMPT_HASH = hashlib.sha256(b"".join(f.read_bytes() for f in _files)).hexdigest()
SET_VERSION = yaml.safe_load((REPO / "challenge/eval/questions.yaml").read_text())["set_version"]
_git = lambda *a: subprocess.run(["git", "-C", str(REPO), *a], capture_output=True, text=True).stdout.strip() if shutil.which("git") else ""  # noqa: E731
GIT_SHA = _git("rev-parse", "HEAD") or ENV.get("AGENT_GIT_SHA", "")  # a deployment package carries the sha in its env
GIT_DIRTY = bool(_git("status", "--porcelain"))

_MAX_ROWS = 500  # shortcut: rows past 500 are dropped and truncated=true, raise if a question needs more


def _cell(v):
    """JSON-safe cells: psycopg gives Decimal for numeric and date objects for dates."""
    return float(v) if isinstance(v, Decimal) else v.isoformat() if isinstance(v, date) else v


def _query(sql: str, params=(), user: str | None = None, password: str | None = None) -> dict:
    """One statement on one autocommit connection: {columns, rows}. The default is the read-only agent role (its
    statement_timeout, read-only transactions and search_path are set on the role); the harness passes the owner."""
    with psycopg.connect(host=ENV["PGHOST"], port=ENV.get("PGPORT", "5432"), dbname=ENV["PGDATABASE"],
                         user=user or ENV["AGENT_PGUSER"], password=password or ENV["AGENT_PGPASSWORD"],
                         sslmode=ENV.get("PGSSLMODE", "require"), autocommit=True) as conn:
        cur = conn.execute(sql, params or None)  # no params: a % in the SQL (LIKE 'RETIREMENT%') is not a placeholder
        return {"columns": [d.name for d in cur.description], "rows": [[_cell(v) for v in r] for r in cur.fetchall()]}


def _result(body: dict, tool_use_id: str | None = None) -> dict:
    """A tool result in the shape _result_stats and run_turn read; rows past _MAX_ROWS dropped, truncated flagged."""
    rows = body["rows"]
    body.update(rows=rows[:_MAX_ROWS], row_count=len(rows), truncated=len(rows) > _MAX_ROWS)
    return {**({"toolUseId": tool_use_id} if tool_use_id else {}), "status": "success",
            "content": [{"text": redact(json.dumps(body, default=str))}]}


# The eight governed calculations: semantic.<name>(...) in Postgres, fixed SQL the model cannot edit. Descriptions are
# the function and parameter COMMENTs from notebooks/03_semantic.sql, which the Databricks MCP server used to serve.
_DATE = "Date as YYYY-MM-DD. "
_COMP = "Component code, e.g. HSBC (TSA), HSBD (CBP), HSCB (FEMA), HSCA (CISA); NULL for all of DHS"
_SERIES = "Four-digit occupational series, e.g. 1802 (TSA screeners), 1895 (CBP officers); NULL for all"
FUNCTIONS = {  # name: (description, {param: description}); every param is a string or null (see _null_args)
    "headcount": (
        "Question family 1: how many people a component or occupation has, and in which states. One row per duty "
        "station state, largest first. headcount_location_imputed rows have a synthetic state drawn from USAJOBS "
        "postings (where DHS hires, not where staff sit); say so when it is a large share, and quote "
        "imputation_quality(). source_file is the OPM snapshot file used",
        {"as_of_month": _DATE + "Snapshot month, 2025-09-01 to 2026-08-01 (latest); any day in the month works",
         "component": _COMP, "series": _SERIES}),
    "separation_rate": (
        "Question family 2: attrition over the trailing twelve months (effective months as_of_month - 11 to "
        "as_of_month), with and without the 2025 deferred resignation program (DRP) wave. rate = separations / "
        "mean(headcount_start, headcount_end); headcount_start is the snapshot at as_of_month - 11. Separations "
        "counted by effective_month across all monthly files (files_used); about 0.8% are detectable restatements. "
        "Right-censored: late reports keep arriving, so recent counts will grow",
        {"as_of_month": _DATE + "Last month of the trailing twelve; only 2026-08-01 has a start snapshot (earlier "
                                "months return NULL rates)",
         "component": _COMP, "series": _SERIES}),
    "attrition_ranking": (
        "Question family 3: which component x series cells are losing people fastest. Same columns and rules as "
        "separation_rate, one row per cell, ranked by rate (highest first). Compare rate with rate_excl_drp: the "
        "2025 DRP wave dominates some cells. Right-censored: recent counts will grow",
        {"as_of_month": _DATE + "Last month of the trailing twelve; use 2026-08-01 (the only month with a start snapshot)",
         "min_headcount": "Smallest cell to rank, by headcount at as_of_month, e.g. 100; small cells have noisy rates",
         "top_n": "How many cells to return, e.g. 10"}),
    "length_of_service_profile": (
        "Question family 4: how tenure-heavy a cell is, and whether a retirement cliff is forming. Headcount by "
        "years of federal service in buckets <1, 1-3, 3-5, 5-10, 10-20, 20+ (lower bound inclusive), with each "
        "bucket share of the cell. Published OPM values, not imputed. source_file is the snapshot used",
        {"as_of_month": _DATE + "Snapshot month, 2025-09-01 to 2026-08-01 (latest)", "component": _COMP, "series": _SERIES}),
    "open_postings": (
        "Question family 5: what USAJOBS postings are advertised against a cell on a date. Open means open_date <= "
        "as_of_date AND close_date >= as_of_date; for a past date that is an upper bound, since postings filled or "
        "cancelled before their close date are invisible. total_openings is NULL when the posting says Many or Few "
        "(total_openings_raw has the text). Closing soonest first",
        {"as_of_date": _DATE + "Date the postings were open; postings cover 2025-09-01 to 2026-10-31",
         "component": _COMP, "series": _SERIES + ". Matches any series a posting lists"}),
    "posting_coverage": (
        "Question family 6: is advertised hiring aimed at where people are leaving. separations_ttm counts effective "
        "months (month of as_of_date) - 11 to that month across all OPM files (files_used); OPM data ends 2026-08, "
        "so later dates see fewer months. open_postings is an upper bound (open_date <= date AND close_date >= "
        "date). openings_known sums stated openings; postings_many_or_few say Many or Few and are not in the sum. "
        "coverage_ratio = openings_known / separations_ttm. Right-censored",
        {"as_of_date": _DATE + "Date to count open postings; separations are the twelve effective months ending in its month",
         "component": _COMP, "series": _SERIES}),
    "plan_variance": (
        "Question family 7: how a quarter of hiring landed against the staffing plan, and why. The plan is SYNTHETIC "
        "(is_synthetic, generation_rule say how it was made); say so. actual_accessions counts accessions effective "
        "in the quarter in the planned cells, across all OPM files (files_used). variance = actual - planned; "
        "variance_pct = variance / planned. TSA 1802 and CBP 1895 FY2026 Q1 to Q3 are stress cells. Right-censored: "
        "later files add accessions",
        {"fiscal_quarter": "Fiscal quarter as FY2026Q1 (Oct to Dec 2025) through FY2027Q4; accessions exist through "
                           "FY2026Q4 (July and August only)",
         "component": "Component code, e.g. HSBD (CBP); NULL for every planned cell", "series": _SERIES}),
    "imputation_quality": (
        "Question family 8: how much to trust a location answer that rests on imputed rows. Masking test: FEMA and "
        "CISA August 2026 rows with published location were re-imputed as if redacted; state_match_share is how "
        "often the drawn state equals the true one, state_overlap how similar the two state distributions are (1 = "
        "identical). It flatters the method for TSA and CBP, whose staff spread over hundreds of airports and ports. "
        "Quote it with any imputed-location answer",
        {}),
}


def _function_tool(name: str) -> PythonAgentTool:
    desc, params = FUNCTIONS[name]
    sql = f"SELECT * FROM semantic.{name}({', '.join(f'{p} => %s' for p in params)})"  # named notation: the SQL's order

    def run(tool_use, **_):
        try:
            return _result(_query(sql, [tool_use["input"].get(p) for p in params]), tool_use["toolUseId"])
        except Exception as e:  # noqa: BLE001  (the model answers from another calculation or says it is unavailable)
            return {"toolUseId": tool_use["toolUseId"], "status": "error", "content": [{"text": redact(f"{type(e).__name__}: {e}")}]}

    schema = {"type": "object", "required": list(params),
              "properties": {p: {"type": ["string", "null"], "description": d} for p, d in params.items()}}
    return PythonAgentTool(name, {"name": name, "description": desc, "inputSchema": {"json": schema}}, run)


@tool
def one_off_query(sql: str) -> dict:
    """A one-off query for a question the review's standard calculations do not cover: one read-only SELECT you
    write, Postgres dialect, against the views in schema semantic (the data fields skill lists them). Filter on the
    period and the population in full. Returns the SQL as sent, columns, rows (at most 500), row_count, truncated.

    Args:
        sql: One SELECT statement, no trailing semicolon.
    """
    try:
        # The wrap enforces one statement and the row cap; the read-only role and its timeout are the real fence.
        body = _query(f"SELECT * FROM ({sql.strip().rstrip(';')}) q LIMIT {_MAX_ROWS + 1}")
        return _result({"sql": sql, "statement_id": hashlib.sha256(sql.encode()).hexdigest()[:16], **body})
    except Exception as e:  # noqa: BLE001  (the model answers from a calculation or says it is unavailable)
        return {"status": "error", "content": [{"text": redact(f"one-off query failed: {type(e).__name__}: {e}")}]}


class _RedactedFile:
    """Span sink: tool results and errors can carry the host or a password."""

    def __init__(self, path: Path):
        self.f = open(path, "a")  # noqa: SIM115  (lives for the process)

    def write(self, s: str) -> None:
        self.f.write(redact(s))

    def flush(self) -> None:
        self.f.flush()


_spans, _spans_lock = None, threading.Lock()


def build_agent(session_id: str, run_index: int = 0, messages: list | None = None, callback_handler=None) -> Agent:
    """messages preloads prior turns (a stateless caller replays the transcript); callback_handler receives every
    streamed event (Strands routes the blocking call through it too), so run_turn stays the one trace writer."""
    global _spans
    RAW.mkdir(exist_ok=True)
    day = datetime.now(timezone.utc).date().isoformat()
    with _spans_lock:  # parallel eval workers build agents at once; one span file per process
        if _spans is None:  # the tracer provider is global
            _spans = _RedactedFile(RAW / f"{day}-{session_id}-spans.log")
            StrandsTelemetry().setup_console_exporter(out=_spans)
    model = AnthropicModel(client_args={"api_key": ENV["ANTHROPIC_API_KEY"]}, model_id=MODEL_ID, max_tokens=MAX_TOKENS,
                           cache_config=CacheConfig(strategy="anthropic"),
                           params={"output_config": {"effort": EFFORT}})
    # Sequential: one connection per live agent (16 eval workers = 16), within a db.t4g.micro's limit.
    agent = Agent(model=model, tools=[*map(_function_tool, FUNCTIONS), one_off_query], tool_executor=SequentialToolExecutor(),
                  system_prompt=SYSTEM, callback_handler=callback_handler, messages=messages)
    durations = {}
    agent.add_hook(lambda e: durations.__setitem__(e.tool_use["toolUseId"], e.duration), AfterToolCallEvent)
    agent.add_hook(_null_args, BeforeToolCallEvent)
    agent.trace = {"session_id": session_id, "run_index": run_index, "n": 0, "prev_answer": None,
                   "durations": durations, "path": RAW / f"{day}-{session_id}-trace.jsonl"}
    return agent


def _null_args(event) -> None:
    """The calculations' schema types every argument as a string, so the model writes "null" for "all of DHS";
    the string matches nothing and returns zero rows. Send a real null, which the functions read as "all"."""
    if event.tool_use["name"] in FUNCTIONS:
        args = event.tool_use.get("input") or {}
        for k, v in args.items():
            if isinstance(v, str) and v.strip().lower() in ("null", "none", ""):
                args[k] = None


def _norm(name: str) -> str:
    # "genie" is the trace label of the exploratory tool, kept from the Genie era so history and dashboards compare.
    return "genie" if name in ("one_off_query", "one-off query") else name


_FENCE = re.compile(r"```[\w-]*[ \t]*\n(.*?)```", re.S)


def _split_block(text: str):
    """Return (prose, block) from the last fenced block, or (text, None) when it is missing or not the JSON contract."""
    fences = list(_FENCE.finditer(text))
    if fences:
        try:
            block = json.loads(fences[-1].group(1))
            if isinstance(block, dict) and "answer_value" in block and isinstance(block.get("cited_tools"), list):
                m = fences[-1]
                return (text[: m.start()] + text[m.end():]).strip(), block
        except json.JSONDecodeError:
            pass
    return text.strip(), None


def _result_stats(result: dict) -> dict:
    text = "".join(c.get("text", "") for c in result.get("content", []))
    try:
        body = json.loads(text)
    except json.JSONDecodeError:
        body = {}
    body = body if isinstance(body, dict) else {}
    cols, rows = body.get("columns") or [], body.get("rows") or []
    col = lambda n: [r[cols.index(n)] for r in rows] if n in cols else []  # noqa: E731
    flags = [i for i, n in enumerate(cols) if n in ("location_imputed", "pay_imputed")]
    imputed = sum(v or 0 for v in col("headcount_location_imputed")) + sum(1 for r in rows if any(r[i] is True for i in flags))
    return {"result_rows": len(rows), "imputed_rows": imputed, "synthetic_rows": sum(1 for v in col("is_synthetic") if v is True),
            "is_truncated": body.get("is_truncated", body.get("truncated")), "status": result.get("status"), "body": body,
            # Small results kept whole so an answer given from memory can be checked against what the tool returned.
            "result_values": {"columns": cols, "rows": rows} if len(rows) <= 50 else None}


def _model_error(e: BaseException) -> bool:
    while e is not None:
        if isinstance(e, (anthropic.APIError, ModelThrottledException, ContextWindowOverflowException)):
            return True
        e = e.__cause__ or e.__context__
    return False


def run_turn(agent: Agent, text: str, q_id: str | None = None, context: str | None = None, extra: dict | None = None,
             scope: str | None = None) -> dict:
    st = agent.trace
    st["n"] += 1
    if context:
        about = f" about {scope}" if scope else ""
        msg = f"The analyst supplies this fact{about}, which the data does not contain: {context}" + (f"\n\n{text}" if text else "")
    else:
        msg = text
    start = len(agent.messages)
    st["durations"].clear()
    before = dict(agent.event_loop_metrics.accumulated_usage)
    error = detail = stop = None
    t0 = time.perf_counter()
    try:
        stop = agent(msg).stop_reason
    except MaxTokensReachedException as e:
        error, detail = "max_tokens", e
    except Exception as e:  # noqa: BLE001  (every turn writes a line; the session loop never shows a traceback)
        error, detail = ("model" if _model_error(e) else "tool"), e
    latency_ms = round((time.perf_counter() - t0) * 1000)
    usage = {k: agent.event_loop_metrics.accumulated_usage.get(k, 0) - before.get(k, 0) for k in PRICE}

    calls, results, answer = [], {}, ""
    for m in agent.messages[start:]:
        for b in m["content"]:
            if "toolUse" in b:
                calls.append(b["toolUse"])
            elif "toolResult" in b:
                results[b["toolResult"]["toolUseId"]] = b["toolResult"]
        if m["role"] == "assistant":
            answer = "".join(b.get("text", "") for b in m["content"]) or answer
    tool_calls, genie_sql, genie_statement_id = [], None, None
    for c in calls:
        stats = _result_stats(results.get(c["toolUseId"], {}))
        body = stats.pop("body")
        if _norm(c["name"]) == "genie" and isinstance(body, dict) and body.get("sql"):
            genie_sql, genie_statement_id = body["sql"], body.get("statement_id") or body.get("message_id")
        d = st["durations"].get(c["toolUseId"])
        tool_calls.append({"name": _norm(c["name"]), "params": c.get("input"), **stats,
                           "duration_ms": round(d * 1000) if d is not None else None})

    prose, block = _split_block(answer)
    if error is None and stop == "refusal":
        error = "refusal"
    if error is None and tool_calls and tool_calls[-1]["status"] == "error":
        error = "tool"
    if error is None and block is None:
        error = "format"
    line = {
        "ts": datetime.now(timezone.utc).isoformat(timespec="seconds"), "session_id": st["session_id"],
        "run_index": st["run_index"], "set_version": SET_VERSION, "q_id": q_id or f"A{st['n']:02d}",
        "agent_git_sha": GIT_SHA, "git_dirty": GIT_DIRTY, "prompt_hash": PROMPT_HASH, "model_id": MODEL_ID, "effort": EFFORT, "max_tokens": MAX_TOKENS,
        "provider_served": "anthropic", "stop_reason": stop, "question_text": msg, "supplied_context": context,
        "turn_1_answer_text": st["prev_answer"] if context else None, "tool_calls": tool_calls,
        "genie_sql": genie_sql, "genie_statement_id": genie_statement_id, "answer_text": prose,
        "answer_value": block.get("answer_value") if block else None,
        "cited_tools": [_norm(t) for t in block["cited_tools"]] if block else [],
        "latency_ms": latency_ms, "input_tokens": usage["inputTokens"], "output_tokens": usage["outputTokens"],
        "cache_read_tokens": usage["cacheReadInputTokens"], "cache_write_tokens": usage["cacheWriteInputTokens"],
        "cost_usd": round(sum(usage[k] * p for k, p in PRICE.items()) / 1e6, 6), "error": error,
        "error_detail": f"{type(detail).__name__}: {detail}"[:500] if detail else None,
        **(extra or {}),  # caller fields such as the web app's task number
    }
    out = redact(json.dumps(line, default=str))
    with open(st["path"], "a") as f:
        f.write(out + "\n")
    st["prev_answer"] = prose
    return json.loads(out)
