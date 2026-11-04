"""The demo app: the workshop page with the live agent in its sidebar, and the eval dashboard.

Run: RAW_DIR=<repo>/raw challenge/.venv/bin/python -m uvicorn main:app --app-dir challenge/app --port 8766
Stateless: every /api/ask carries the transcript; the answer streams back as server-sent events. Deployed as one
container on Lambda behind a streaming Function URL (Dockerfile at the repo root, challenge/infra/app.tf): uvicorn on
8080 under the Lambda Web Adapter, static files served from here, configuration from the environment only
(ANTHROPIC_API_KEY or ANTHROPIC_API_KEY_SSM, PG*, AGENT_PG*, REVIEWER_PG*, RAW_DIR, AGENT_GIT_SHA), /health for readiness.
"""

import json
import sys
from pathlib import Path
from typing import Literal

from fastapi import FastAPI, HTTPException
from fastapi.responses import FileResponse, StreamingResponse
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel, Field

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parents[0] / "prototype"))
from app import render, split_label  # noqa: E402  the tester app's markdown-to-HTML and label line

import backend  # noqa: E402
import evals  # noqa: E402

app = FastAPI(title="Lantern Workshop")
CELL = HERE / "data/cell.json"


class Turn(BaseModel):
    role: str
    text: str


class Ask(BaseModel):
    text: str = ""
    context: str | None = None
    turns: list[Turn] = []
    session_id: str = Field("app", pattern=r"^[A-Za-z0-9_-]{1,40}$")  # it names the trace file; keep it out of paths


async def sse(events):
    """Frames an event stream. Every stream ends with exactly one done frame then EOF: an exception becomes a done frame
    with error "agent", never a truncated body the browser reads as a network failure."""
    done = False
    try:
        async for ev in events:
            if "done" in ev:
                row = ev["done"]
                label, rest = split_label(row.get("answer_text") or "")
                ev = {"done": {**row, "label": label, "body_html": render(rest) if label else render(row.get("answer_text") or "")}}
                done = True
            yield f"data: {json.dumps(ev, default=str)}\n\n"
    except Exception as e:  # noqa: BLE001
        if not done:
            yield f"data: {json.dumps({'done': {'error': 'agent', 'error_detail': type(e).__name__, 'answer_text': '', 'body_html': '', 'label': None}})}\n\n"


@app.post("/api/ask")
async def ask(req: Ask):
    if not req.text.strip() and not (req.context or "").strip():
        raise HTTPException(400, "empty question")
    turns = [t.model_dump() for t in req.turns]
    try:
        backend.messages(turns)
    except ValueError as e:
        raise HTTPException(400, str(e)) from e
    sid = req.session_id if req.session_id.startswith("app-") else f"app-{req.session_id}"
    return StreamingResponse(sse(backend.stream(turns, req.text.strip(), (req.context or "").strip() or None, sid)),
                             media_type="text/event-stream", headers={"Cache-Control": "no-store", "X-Accel-Buffering": "no"})


class Decision(BaseModel):
    rec: str = Field(pattern=r"^[a-z0-9-]{1,40}$")
    verdict: Literal["accept", "edit", "dismiss"]
    text: str = Field(min_length=1, max_length=1000)
    session_id: str = Field("app", pattern=r"^[A-Za-z0-9_-]{1,40}$")


@app.post("/api/decision")
def decision(d: Decision):
    if not d.text.strip():
        raise HTTPException(400, "empty recommendation")
    try:
        return backend.record(d.rec, d.verdict, d.text.strip(), d.session_id)
    except Exception as e:  # noqa: BLE001  the type only: a psycopg message can carry the host
        print(f"decision not recorded: {type(e).__name__}", file=sys.stderr)
        raise HTTPException(503, "decision not recorded") from None


@app.get("/api/cell")
def cell():
    return json.loads(CELL.read_text())


@app.get("/api/evals")
def evals_data():
    return evals.load()


@app.get("/")
def index():
    return FileResponse(HERE / "static/index.html")


@app.get("/evals")
def evals_page():
    return FileResponse(HERE / "static/evals.html")


@app.get("/health")
def health():
    return {"ok": True}


PAGES = {"study": "study.html", "mission": "mission.html", "incident": "incident.html", "transcript": "transcript.html",
         "architecture": "architecture.html"}


@app.get("/{page}")
def static_page(page: str):
    if page not in PAGES:
        raise HTTPException(404)
    return FileResponse(HERE / "static" / PAGES[page])  # after the fixed routes: it matches any one-segment path


app.mount("/static", StaticFiles(directory=HERE / "static"), name="static")
