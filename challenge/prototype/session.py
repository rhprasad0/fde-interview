"""Spec 05 step 3: the terminal session loop. Run: challenge/.venv/bin/python -B challenge/prototype/session.py

Commands: /q A07 tags the next turn; /context <fact> sends the fact as the analyst's supplied context;
/new starts a fresh agent, token, and session id. Anything else is sent verbatim.
"""

import uuid

from agent import build_agent, redact, run_turn
from strands.hooks import BeforeToolCallEvent

DIM, OFF = "\033[2m", "\033[0m"


def main() -> None:
    agent, sid, q_id = None, f"s-{uuid.uuid4().hex[:8]}", None
    print(f"{DIM}session {sid}. /q <id>, /context <fact>, /new{OFF}")
    while True:
        try:
            line = input("\n> ").strip()
        except (EOFError, KeyboardInterrupt):
            break
        if not line:
            continue
        if line.startswith("/q "):
            q_id = line[3:].strip()
            continue
        if line == "/new":
            if agent is not None:
                try:
                    agent.cleanup()
                except Exception:  # noqa: BLE001,S110  (a dead client must not block recovery)
                    pass
            agent, sid = None, f"s-{uuid.uuid4().hex[:8]}"
            print(f"{DIM}new session {sid}{OFF}")
            continue
        context = line[len("/context "):].strip() if line.startswith("/context ") else None
        try:
            if agent is None:  # built at the first question: the token lives one hour
                agent = build_agent(sid)
                agent.add_hook(lambda e: print(f"{DIM}working...{OFF}", flush=True), BeforeToolCallEvent)
            r = run_turn(agent, "" if context else line, q_id=q_id, context=context)
        except (Exception, KeyboardInterrupt) as e:  # noqa: BLE001  (never a traceback on the shared screen; Ctrl-C a stuck turn, then /new)
            print(f"one moment\n{DIM}{redact(type(e).__name__)}{OFF}")
            continue
        finally:
            q_id = None
        print("one moment" if r["error"] == "model" or not r["answer_text"] else r["answer_text"])
        tools = ", ".join(c["name"] for c in r["tool_calls"]) or "no tools"
        print(f"{DIM}{r['q_id']} | {tools} | {r['latency_ms'] / 1000:.1f}s | error={r['error']}{OFF}")


if __name__ == "__main__":
    main()
