"""The agent seam. stream(turns, text, context, session_id) yields {"delta": str} | {"tool": name} | {"ping": True}
and then exactly one {"done": row}, where row is run_turn's trace dict.

Local: the Strands agent runs in this process, one fresh agent per request, prior turns replayed as text. Later: a
stream_agentcore with the same signature re-yields the data: lines of invoke_agent_runtime, chosen by AGENT_RUNTIME_ARN;
main.py does not change. The browser holds the transcript, so the model sees prior text, not prior tool results.
"""

import asyncio
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "prototype"))
import agent as A  # noqa: E402

SCOPE = "CBP Officers, FY2026 Q1"  # the cell the page is open on; attached to context turns, as the tester app does
ROLES = ("user", "assistant")


def messages(turns: list[dict]) -> list[dict]:
    """Browser turns to Strands messages. A blank user turn makes Strands raise on every later call, so refuse it here."""
    out = []
    for t in turns:
        role, text = t.get("role"), str(t.get("text") or "").strip()
        if role not in ROLES or not text:
            raise ValueError("each turn needs a role of user or assistant and non-blank text")
        out.append({"role": role, "content": [{"text": text}]})
    return out


async def stream(turns: list[dict], text: str, context: str | None, session_id: str):
    msgs = messages(turns)
    loop, q, seen = asyncio.get_running_loop(), asyncio.Queue(), set()

    def cb(**ev):  # runs on the agent's thread; Strands calls it for every streamed event of the blocking call
        if "data" in ev:
            loop.call_soon_threadsafe(q.put_nowait, {"delta": ev["data"]})
        tu = ev.get("current_tool_use")
        if tu and tu.get("toolUseId") not in seen:
            seen.add(tu["toolUseId"])
            loop.call_soon_threadsafe(q.put_nowait, {"tool": A._norm(tu.get("name") or "")})

    agent = await asyncio.to_thread(A.build_agent, session_id, messages=msgs, callback_handler=cb)
    agent.trace["n"] = sum(m["role"] == "user" for m in msgs)  # the default q_id counts turns, as on a long-lived agent
    if context:
        agent.trace["prev_answer"] = next((m["content"][0]["text"] for m in reversed(msgs) if m["role"] == "assistant"), None)
    fut = loop.run_in_executor(None, lambda: A.run_turn(agent, text, context=context, scope=SCOPE if context else None,
                                                        extra={"client": "app"}))
    fut.add_done_callback(lambda f: q.put_nowait(None))  # runs on the loop, after every delta already queued (FIFO)
    try:
        while True:
            try:
                ev = await asyncio.wait_for(q.get(), 15)
            except TimeoutError:
                yield {"ping": True}  # a long model turn can go quiet; keep the connection open
                continue
            if ev is None:
                break
            yield ev
        yield {"done": fut.result()}
    finally:
        if not fut.done():
            agent.cancel()  # the client went away; stop the model call so the worker thread frees up
        await asyncio.to_thread(agent.cleanup)
