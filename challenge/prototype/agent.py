"""Spec 05: the prototype agent, its MCP clients, and the trace writer.

build_agent(session_id) -> Agent; run_turn(agent, text, q_id=None, context=None) -> trace line dict.
Reads challenge/.env itself; never prints or writes a host, id, secret, or token (see redact).
"""

import hashlib
import json
import re
import subprocess
import time
from contextlib import asynccontextmanager
from datetime import datetime, timedelta, timezone
from pathlib import Path

import anthropic
import httpx
import httpx2  # the transport mcp>=2 requires
import yaml
from mcp.client.streamable_http import streamable_http_client
from strands import Agent, tool
from strands.hooks import AfterToolCallEvent
from strands.models.anthropic import AnthropicModel
from strands.models.model import CacheConfig
from strands.telemetry import StrandsTelemetry
from strands.tools.mcp import MCPClient
from strands.types.exceptions import ContextWindowOverflowException, MaxTokensReachedException, ModelThrottledException

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[1]
RAW = REPO / "raw"

ENV = {}
for _line in (REPO / "challenge/.env").read_text().splitlines():
    _k, _sep, _v = _line.split("#", 1)[0].partition("=")
    if _sep:
        ENV[_k.strip()] = _v.strip().strip("'\"")

HOST = ENV["DATABRICKS_HOST"].rstrip("/")
SPACE = ENV["DATABRICKS_GENIE_SPACE_ID"]
SCOPE = "unity-catalog genie"  # must be a subset of the secret's scopes; "all-apis" is refused
MODEL_ID = "claude-haiku-5-5"
PRICE = {"inputTokens": 0.10, "outputTokens": 0.50, "cacheReadInputTokens": 0.01, "cacheWriteInputTokens": 0.125}  # $/MTok; cache read 0.1x, 5-min write 1.25x
FN_PREFIX = "workforce__semantic__"

_SECRETS = {HOST: "<workspace>", HOST.removeprefix("https://"): "<workspace>", SPACE: "<space>",
            ENV["DATABRICKS_CLIENT_ID"]: "<client-id>", ENV["DATABRICKS_CLIENT_SECRET"]: "<secret>",
            ENV.get("DATABRICKS_WAREHOUSE_ID", ""): "<warehouse>", ENV.get("ANTHROPIC_API_KEY", ""): "<key>"}


def redact(s: str) -> str:
    for v, p in sorted(_SECRETS.items(), key=lambda kv: -len(kv[0])):
        if v:
            s = s.replace(v, p)
    return s


_files = [HERE / "prompt.md", *sorted((HERE / "skills").glob("*.md"))]
SYSTEM = "\n\n".join(f.read_text() for f in _files)
PROMPT_HASH = hashlib.sha256(b"".join(f.read_bytes() for f in _files)).hexdigest()
SET_VERSION = yaml.safe_load((REPO / "challenge/eval/questions.yaml").read_text())["set_version"]
GIT_SHA = subprocess.run(["git", "-C", str(REPO), "rev-parse", "HEAD"], capture_output=True, text=True).stdout.strip()
GIT_DIRTY = bool(subprocess.run(["git", "-C", str(REPO), "status", "--porcelain"], capture_output=True, text=True).stdout.strip())


def _token() -> str:
    r = httpx.post(f"{HOST}/oidc/v1/token", auth=(ENV["DATABRICKS_CLIENT_ID"], ENV["DATABRICKS_CLIENT_SECRET"]),
                   data={"grant_type": "client_credentials", "scope": SCOPE}, timeout=30)
    r.raise_for_status()
    tok = r.json()["access_token"]
    _SECRETS[tok] = "<token>"
    return tok


@asynccontextmanager
async def _connect(url: str):
    # streamable_http_client does not close a client it is handed, so the AsyncClient is entered here.
    async with (
        httpx2.AsyncClient(headers={"Authorization": f"Bearer {_token()}"}, timeout=60) as http,
        streamable_http_client(url, http_client=http) as streams,
    ):
        yield streams


# Genie message states that mean "keep polling"; anything else is terminal.
_GENIE_PENDING = {"SUBMITTED", "FILTERING_CONTEXT", "FETCHING_METADATA", "ASKING_AI", "PENDING_WAREHOUSE", "EXECUTING_QUERY"}
_MAX_ROWS = 500  # shortcut: rows past 500 are dropped and truncated=true, raise if a question needs more


def _structured(res) -> dict:
    text = "".join(c.get("text", "") for c in res["content"])
    if res["status"] == "error":
        raise RuntimeError(text[:500])
    return res.get("structuredContent") or json.loads(text)


def _cell(v: dict, type_name: str):
    s = v.get("string_value")
    if s is None:
        return None
    if type_name in ("LONG", "INT", "SHORT", "BYTE"):
        return int(s)
    if type_name in ("DOUBLE", "FLOAT", "DECIMAL"):
        return float(s)
    if type_name == "BOOLEAN":
        return s.lower() == "true"
    return s


def _genie(question: str) -> dict:
    """Query-then-poll on the Genie space; a fresh MCP session per call (ids are Genie-side, not session-side)."""
    with MCPClient(lambda: _connect(f"{HOST}/api/2.0/mcp/genie/{SPACE}")) as c:
        names = [t.tool_name for t in c.list_tools_sync()]
        ask = next(n for n in names if n.startswith("query_space_"))
        poll = next(n for n in names if n.startswith("poll_response_"))
        wait = timedelta(seconds=120)
        deadline = time.monotonic() + 120
        r = _structured(c.call_tool_sync("ask", ask, {"query": question}, read_timeout_seconds=wait))
        while r["status"] in _GENIE_PENDING and time.monotonic() < deadline:
            time.sleep(2)
            ids = {"conversation_id": r["conversationId"], "message_id": r["messageId"]}
            r = _structured(c.call_tool_sync("poll", poll, ids, read_timeout_seconds=wait))
    content = r.get("content") or {}
    if r["status"] != "COMPLETED":
        raise RuntimeError(f"one-off query ended {r['status']}: {content.get('textAttachments')}")
    qa = (content.get("queryAttachments") or [{}])[0]
    sr = qa.get("statement_response") or {}
    manifest = sr.get("manifest") or {}
    cols = (manifest.get("schema") or {}).get("columns") or []
    data = (sr.get("result") or {}).get("data_array") or []
    total = manifest.get("total_row_count", len(data))
    return {
        "sql": qa.get("query"), "statement_id": sr.get("statement_id"), "message_id": r.get("messageId"),
        "columns": [c["name"] for c in cols],
        "rows": [[_cell(v, c["type_name"]) for v, c in zip(row["values"], cols)] for row in data[:_MAX_ROWS]],
        "row_count": total, "truncated": bool(manifest.get("truncated")) or total > min(len(data), _MAX_ROWS),
        "text": content.get("textAttachments") or [],
    }


@tool
def one_off_query(question: str) -> dict:
    """A one-off query for a question the review's standard calculations do not cover.

    Pass the whole question in plain English with component and series codes, dates, and filters;
    each call is standalone. Returns the generated SQL, statement_id, columns, rows (numbers typed),
    row_count, truncated, and any text reply. Slow: 20 to 60 seconds.

    Args:
        question: The full question, self-contained.
    """
    try:
        return {"status": "success", "content": [{"text": redact(json.dumps(_genie(question)))}]}
    except Exception as e:  # noqa: BLE001  (the model answers from a function or says it is unavailable)
        return {"status": "error", "content": [{"text": redact(f"one-off query failed: {type(e).__name__}: {e}")}]}


class _RedactedFile:
    """Span sink: the inner Genie client's spans carry the space id in tool names."""

    def __init__(self, path: Path):
        self.f = open(path, "a")  # noqa: SIM115  (lives for the process)

    def write(self, s: str) -> None:
        self.f.write(redact(s))

    def flush(self) -> None:
        self.f.flush()


_spans = None


def build_agent(session_id: str, run_index: int = 0) -> Agent:
    global _spans
    RAW.mkdir(exist_ok=True)
    day = datetime.now(timezone.utc).date().isoformat()
    if _spans is None:  # one span file per process; the tracer provider is global
        _spans = _RedactedFile(RAW / f"{day}-{session_id}-spans.log")
        StrandsTelemetry().setup_console_exporter(out=_spans)
    model = AnthropicModel(client_args={"api_key": ENV["ANTHROPIC_API_KEY"]}, model_id=MODEL_ID, max_tokens=16000,
                           cache_config=CacheConfig(strategy="anthropic"))
    functions = MCPClient(lambda: _connect(f"{HOST}/api/2.0/mcp/functions/workforce/semantic"))
    agent = Agent(model=model, tools=[functions, one_off_query], system_prompt=SYSTEM, callback_handler=None)
    durations = {}
    agent.add_hook(lambda e: durations.__setitem__(e.tool_use["toolUseId"], e.duration), AfterToolCallEvent)
    agent.trace = {"session_id": session_id, "run_index": run_index, "n": 0, "prev_answer": None,
                   "durations": durations, "path": RAW / f"{day}-{session_id}-trace.jsonl"}
    return agent


def _norm(name: str) -> str:
    name = name.removeprefix(FN_PREFIX)
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
            "is_truncated": body.get("is_truncated", body.get("truncated")), "status": result.get("status"), "body": body}


def _model_error(e: BaseException) -> bool:
    while e is not None:
        if isinstance(e, (anthropic.APIError, ModelThrottledException, ContextWindowOverflowException)):
            return True
        e = e.__cause__ or e.__context__
    return False


def run_turn(agent: Agent, text: str, q_id: str | None = None, context: str | None = None) -> dict:
    st = agent.trace
    st["n"] += 1
    if context:
        msg = f"The analyst supplies this fact, which the data does not contain: {context}" + (f"\n\n{text}" if text else "")
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
        "agent_git_sha": GIT_SHA, "git_dirty": GIT_DIRTY, "prompt_hash": PROMPT_HASH, "model_id": MODEL_ID,
        "provider_served": "anthropic", "stop_reason": stop, "question_text": msg, "supplied_context": context,
        "turn_1_answer_text": st["prev_answer"] if context else None, "tool_calls": tool_calls,
        "genie_sql": genie_sql, "genie_statement_id": genie_statement_id, "answer_text": prose,
        "answer_value": block.get("answer_value") if block else None,
        "cited_tools": [_norm(t) for t in block["cited_tools"]] if block else [],
        "latency_ms": latency_ms, "input_tokens": usage["inputTokens"], "output_tokens": usage["outputTokens"],
        "cache_read_tokens": usage["cacheReadInputTokens"], "cache_write_tokens": usage["cacheWriteInputTokens"],
        "cost_usd": round(sum(usage[k] * p for k, p in PRICE.items()) / 1e6, 6), "error": error,
        "error_detail": f"{type(detail).__name__}: {detail}"[:500] if detail else None,
    }
    out = redact(json.dumps(line, default=str))
    with open(st["path"], "a") as f:
        f.write(out + "\n")
    st["prev_answer"] = prose
    return json.loads(out)
