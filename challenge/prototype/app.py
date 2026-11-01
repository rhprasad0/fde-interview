"""The review as a local web app with live calls: challenge/.venv/bin/python -B challenge/prototype/app.py

Serves the three screens (/, /quarter, /ask, and their file names, so their relative links resolve) with a
small script injected into each (a task guide bar on all three; live behavior on the brief and the ask screen),
plus /api/ask, /api/new, /api/decide, /api/history, /api/decisions, /api/task, /api/know. One agent per browser
(cookie), built at the first question; every turn writes the agent.py trace line, stamped with the current task.
"""

import html
import json
import re
import threading
import time
import uuid
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlsplit

from agent import RAW, build_agent, redact, run_turn

HOST, PORT = "127.0.0.1", 8765
SCREENS = Path(__file__).resolve().parent / "screens"
PAGES = {"/": "Main", "/Main.dc.html": "Main", "/quarter": "Quarter", "/Quarter.dc.html": "Quarter",
         "/ask": "Ask", "/Ask.dc.html": "Ask"}
LABELS = ("Verified", "Exploratory", "Not available", "Question")
CHOICES = ("accept", "reject", "flag")
DIM, OFF = "\033[2m", "\033[0m"
TOKEN_SECONDS = 3300  # the service principal token lives 3600 s; rebuild before it expires (same as /new)
TASKS = [  # the user-test script: instruction, page, and anchor for each task
    {"text": "Read the draft explanation. What is it telling you? Would you hand it to your director as it stands?", "page": "/", "anchor": ""},
    {"text": "The CHCO's quarterly staffing review is Thursday. Pick the three cells that go on the agenda.", "page": "/quarter", "anchor": ""},
    {"text": "Open one cell and draft the one-paragraph explanation OPM gets. Ask the assistant anything you need.", "page": "/ask", "anchor": ""},
    {"text": "Act on the recommended actions: accept, reject, or flag each one. What should happen next?", "page": "/", "anchor": "recommendations"},
    {"text": "Try to break it. Ask something it should not know or cannot know.", "page": "/ask", "anchor": ""},
]

_sessions, _sessions_lock = {}, threading.Lock()


def _session(cookie_id):
    with _sessions_lock:
        return _sessions.setdefault(cookie_id, {"lock": threading.Lock(), "agent": None, "built": 0.0, "turns": [],
                                                "sid": f"s-{uuid.uuid4().hex[:8]}", "task": 1, "decisions": {}, "know": ""})


def _new(s):
    """As the session loop's /new: fresh agent (built lazily), token, and session id. What the tester sees stays."""
    if s["agent"] is not None:
        try:
            s["agent"].cleanup()
        except Exception:  # noqa: BLE001,S110  (a dead client must not block recovery)
            pass
    s.update(agent=None, built=0.0, sid=f"s-{uuid.uuid4().hex[:8]}")


def _inline(s):
    return re.sub(r"\*\*(.+?)\*\*", r"<strong>\1</strong>", html.escape(s))


def render(text):
    """Prose to minimal HTML: paragraphs, **bold**, fenced blocks as <pre>, pipe tables."""
    out = []
    for i, part in enumerate(re.split(r"```[\w-]*[ \t]*\n(.*?)```", text, flags=re.S)):
        if i % 2:
            out.append('<pre style="margin:0;padding:12px 14px;background:#ffffff;border:1px solid #dfe1e5;border-radius:4px;'
                       f'font-size:13px;line-height:1.45;overflow-x:auto">{html.escape(part.rstrip())}</pre>')
            continue
        for para in re.split(r"\n\s*\n", part.strip()):
            lines = [x.strip() for x in para.strip().split("\n") if x.strip()]
            if len(lines) >= 2 and all(x.startswith("|") for x in lines):
                rows = [[_inline(c.strip()) for c in x.strip("|").split("|")] for x in lines if not re.fullmatch(r"[|:\s-]+", x)]
                head = "".join(f"<th>{c}</th>" for c in rows[0])
                body = "".join("<tr>" + "".join(f"<td>{c}</td>" for c in r) + "</tr>" for r in rows[1:])
                out.append(f'<div style="overflow-x:auto"><table style="width:100%"><thead><tr>{head}</tr></thead><tbody>{body}</tbody></table></div>')
            elif lines:
                out.append('<p style="margin:0">' + "<br>".join(_inline(x) for x in lines) + "</p>")
    return "".join(out)


def split_label(text):
    first, _, rest = (text or "").strip().partition("\n")
    label = first.strip().strip("*").strip()
    return (label, rest) if label in LABELS else (None, text or "")


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):  # the terminal shows one line per turn, not one per request
        pass

    def _cookie(self):
        m = re.search(r"(?:^|;\s*)rid=([0-9a-f]{32})", self.headers.get("Cookie", ""))
        return (m.group(1), False) if m else (uuid.uuid4().hex, True)

    def _send(self, code, body, ctype="application/json", cookie=None):
        data = (body if isinstance(body, str) else json.dumps(body)).encode()
        self.send_response(code)
        self.send_header("Content-Type", f"{ctype}; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "no-store")
        if cookie:
            self.send_header("Set-Cookie", f"rid={cookie}; Path=/; Max-Age=43200; HttpOnly; SameSite=Strict")
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):  # noqa: N802
        path = urlsplit(self.path).path
        rid, fresh = self._cookie()
        if path in PAGES:
            page = (SCREENS / f"{PAGES[path]}.dc.html").read_text()
            script = GUIDE_JS.replace("__TASKS__", json.dumps(TASKS)) + {"Main": MAIN_JS, "Ask": ASK_JS}.get(PAGES[path], "")
            page = page.replace("</body>", f"<script>{script}</script>\n</body>")
            self._send(200, page, "text/html", rid if fresh else None)
        elif path == "/support.js":  # the screens reference it; nothing in it is needed here
            self._send(200, "", "text/javascript")
        elif path in ("/api/history", "/api/decisions", "/api/task", "/api/know"):
            s = _session(rid)
            body = {"/api/history": s["turns"], "/api/decisions": s["decisions"], "/api/task": {"task": s["task"]},
                    "/api/know": {"text": s["know"]}}[path]
            self._send(200, body, cookie=rid if fresh else None)
        else:
            self._send(404, {"error": "not found"})

    def do_POST(self):  # noqa: N802
        path = urlsplit(self.path).path
        rid, fresh = self._cookie()
        try:
            req = json.loads(self.rfile.read(int(self.headers.get("Content-Length") or 0)) or b"{}")
        except json.JSONDecodeError:
            return self._send(400, {"error": "bad json"})
        s = _session(rid)
        cookie = rid if fresh else None
        if path == "/api/ask":
            return self._send(200, self._ask(s, req), cookie=cookie)
        if path == "/api/new":
            with s["lock"]:
                _new(s)
            print(f"{DIM}new session {s['sid']}{OFF}", flush=True)
            return self._send(200, {"ok": True}, cookie=cookie)
        if path == "/api/decide":
            choice, rec = req.get("choice"), str(req.get("recommendation") or "")[:1000]
            if choice not in CHOICES or not rec:
                return self._send(400, {"error": "choice must be accept, reject, or flag, with a recommendation"})
            now = datetime.now(timezone.utc)
            line = {"ts": now.isoformat(timespec="seconds"), "session_id": s["sid"], "task": s["task"], "recommendation": rec,
                    "choice": choice}
            s["decisions"][rec] = choice
            RAW.mkdir(exist_ok=True)
            with open(RAW / f"{now.date().isoformat()}-{s['sid']}-decisions.jsonl", "a") as f:
                f.write(redact(json.dumps(line)) + "\n")
            print(f"{DIM}{s['sid']} task {s['task']} decision | {choice} | {rec[:60]}{OFF}", flush=True)
            return self._send(200, {"ok": True}, cookie=cookie)
        if path == "/api/task":
            n = req.get("task")
            if not isinstance(n, int) or not 1 <= n <= len(TASKS):
                return self._send(400, {"error": f"task must be 1 to {len(TASKS)}"})
            s["task"] = n
            print(f"{DIM}{s['sid']} task {n}{OFF}", flush=True)
            return self._send(200, {"task": n}, cookie=cookie)
        if path == "/api/know":
            s["know"] = str(req.get("text") or "")[:2000]
            return self._send(200, {"ok": True}, cookie=cookie)
        return self._send(404, {"error": "not found"})

    def _ask(self, s, req):
        text, context = str(req.get("text") or "").strip(), (str(req.get("context") or "").strip() or None)
        if not text and not context:
            return {"label": None, "body_html": "", "answer_value": None, "cited_tools": [], "latency_ms": 0, "error": "empty"}
        with s["lock"]:  # one turn at a time per browser; other browsers and pages are not blocked
            if s["agent"] is not None and time.monotonic() - s["built"] > TOKEN_SECONDS:
                _new(s)
            try:
                if s["agent"] is None:
                    s["agent"], s["built"] = build_agent(s["sid"]), time.monotonic()
                r = run_turn(s["agent"], text, q_id=req.get("q_id") or None, context=context, extra={"task": s["task"]})
            except Exception as e:  # noqa: BLE001  (never a traceback; the next question gets a fresh agent)
                print(f"{DIM}{s['sid']} agent failed: {redact(type(e).__name__)}{OFF}", flush=True)
                _new(s)
                return {"label": None, "body_html": "<p style=\"margin:0\">One moment. Please ask that again.</p>",
                        "answer_value": None, "cited_tools": [], "latency_ms": 0, "error": "agent"}
            label, prose = split_label(r["answer_text"])
            failed = r["error"] == "model" or not r["answer_text"]
            body = "<p style=\"margin:0\">One moment. Please ask that again.</p>" if failed else render(prose)
            tools = ", ".join(c["name"] for c in r["tool_calls"]) or "no tools"
            print(f"{DIM}{s['sid']} task {s['task']} {r['q_id']} | {tools} | {r['latency_ms'] / 1000:.1f}s | error={r['error']}{OFF}", flush=True)
            out = {"label": None if failed else label, "body_html": body, "answer_value": r["answer_value"],
                   "cited_tools": r["cited_tools"], "latency_ms": r["latency_ms"], "error": r["error"]}
            s["turns"].append({"question": text or f"You added: {context}", **out})
            if r["error"] == "model":
                _new(s)  # the web equivalent of typing /new after "one moment"
            return out


MAIN_JS = r"""
(() => {
  const post = (u, b) => fetch(u, {method: 'POST', headers: {'Content-Type': 'application/json'}, body: JSON.stringify(b)});
  const reset = o => { o.setAttribute('style', o.dataset.orig); o.textContent = o.dataset.text; o.setAttribute('aria-pressed', 'false'); };
  const press = b => {
    b.parentElement.querySelectorAll('button[data-choice]').forEach(reset);
    b.setAttribute('style', b.dataset.orig + ';background:#162e51;border-color:#162e51;color:#ffffff');
    b.textContent = '✓ ' + b.dataset.text; b.setAttribute('aria-pressed', 'true');
  };
  const recOf = b => b.parentElement.parentElement.querySelector('p').textContent.trim();
  const buttons = [];
  document.querySelectorAll('button').forEach(b => {
    const t = b.textContent.trim();
    const choice = t === 'Accept' ? 'accept' : t === 'Reject' ? 'reject' : t.startsWith('Flag') ? 'flag' : null;
    if (!choice) return;
    Object.assign(b.dataset, {orig: b.getAttribute('style'), text: t, choice}); b.setAttribute('aria-pressed', 'false');
    b.addEventListener('click', async () => { if ((await post('/api/decide', {recommendation: recOf(b), choice})).ok) press(b); });
    buttons.push(b);
  });
  fetch('/api/decisions').then(r => r.json()).then(d => buttons.forEach(b => { if (d[recOf(b)] === b.dataset.choice) press(b); }));
  const f = document.querySelector('form[action="Ask.dc.html"]'), inp = f.querySelector('input');
  const go = e => { e.preventDefault(); const q = inp.value.trim(); location.href = '/ask' + (q ? '?q=' + encodeURIComponent(q) : ''); };
  f.addEventListener('submit', go); f.querySelector('a').addEventListener('click', go);
  f.nextElementSibling.querySelectorAll('a').forEach(a => { a.href = '/ask?q=' + encodeURIComponent(a.textContent.trim()); });
  document.getElementById('recommendations').insertAdjacentHTML('beforeend', `
    <form id="know" style="display: flex; flex-direction: column; gap: 8px; border-top: 1px solid #dfe1e5; padding-top: 16px">
      <label for="knowtext" style="font-size: 15px; font-weight: 600">Add what you know</label>
      <span style="font-size: 13px; color: #4b4f58">A fact the data does not have, such as a hiring pause. The assistant recomputes under it and labels it as your assumption.</span>
      <div style="display: flex; flex-wrap: wrap; gap: 10px">
        <input id="knowtext" type="text" placeholder="For example: no one could be onboarded from October 1 to November 12, 2025" style="flex: 1 1 520px; min-height: 44px; padding: 0 14px; border: 1px solid #565c65; border-radius: 4px; font-size: 15px; font-family: inherit">
        <button type="submit" style="min-height: 44px; padding: 0 18px; border-radius: 4px; border: 1px solid #005ea2; background: #005ea2; color: #ffffff; font-weight: 600; font-size: 14px; cursor: pointer">Add and ask</button>
      </div>
    </form>`);
  const know = document.getElementById('knowtext');
  fetch('/api/know').then(r => r.json()).then(k => { if (!know.value) know.value = k.text; });
  const keep = () => post('/api/know', {text: know.value});
  know.addEventListener('change', keep);
  document.getElementById('know').addEventListener('submit', async e => {
    e.preventDefault(); const c = know.value.trim(); await keep();
    if (c) location.href = '/ask?context=' + encodeURIComponent(c);
  });
})();
"""

GUIDE_JS = r"""
(() => {
  const TASKS = __TASKS__;
  const post = (u, b) => fetch(u, {method: 'POST', headers: {'Content-Type': 'application/json'}, body: JSON.stringify(b)});
  const rec = [...document.querySelectorAll('h2')].find(h => h.textContent.trim() === 'Recommended for the review');
  if (rec) rec.closest('section').id = 'recommendations';
  const btn = 'min-height: 44px; padding: 0 18px; border-radius: 4px; font-weight: 600; font-size: 14px; cursor: pointer; font-family: inherit';
  const bar = document.createElement('div');
  bar.setAttribute('role', 'region'); bar.setAttribute('aria-label', 'Test tasks');
  bar.style.cssText = 'position: fixed; left: 0; right: 0; bottom: 0; z-index: 50; background: #ffffff; border-top: 3px solid #005ea2; box-shadow: 0 -2px 10px rgba(0,0,0,.10)';
  bar.innerHTML = `<div style="max-width: 1120px; margin: 0 auto; padding: 12px 24px; box-sizing: border-box; display: flex; flex-wrap: wrap; align-items: center; gap: 10px 24px">
    <div style="flex: 1 1 480px; display: flex; flex-direction: column; gap: 2px">
      <span data-n style="font-size: 13px; font-weight: 700; color: #005ea2; letter-spacing: .04em; text-transform: uppercase"></span>
      <span data-t style="font-size: 16px; line-height: 1.4; color: #1b1b1b"></span>
    </div>
    <div style="display: flex; gap: 8px; flex: none">
      <button data-back type="button" style="${btn}; border: 1px solid #565c65; background: #ffffff; color: #1b1b1b">Back</button>
      <button data-next type="button" style="${btn}; border: 1px solid #005ea2; background: #005ea2; color: #ffffff">Next task</button>
    </div></div>`;
  document.body.appendChild(bar);
  document.body.style.paddingBottom = '120px';
  const back = bar.querySelector('[data-back]'), next = bar.querySelector('[data-next]');
  let n = 1;
  const show = () => {
    bar.querySelector('[data-n]').textContent = `Task ${n} of ${TASKS.length}`;
    bar.querySelector('[data-t]').textContent = TASKS[n - 1].text;
    back.disabled = n === 1; next.disabled = n === TASKS.length;
    back.style.opacity = back.disabled ? .4 : 1; next.style.opacity = next.disabled ? .4 : 1;
  };
  const go = async m => {
    n = (await (await post('/api/task', {task: m})).json()).task; show();
    const t = TASKS[n - 1];
    location.href = t.page + (t.anchor ? '#' + t.anchor : '');
  };
  back.addEventListener('click', () => go(n - 1)); next.addEventListener('click', () => go(n + 1));
  show();
  fetch('/api/task').then(r => r.json()).then(t => { n = t.task; show(); });
  if (location.hash === '#recommendations' && rec) addEventListener('load', () => rec.scrollIntoView({block: 'start'}));
})();
"""

ASK_JS = r"""
(() => {
  const KIND = {
    'Verified': ['#2e8540', '<path d="M20 6 9 17l-5-5"></path>'],
    'Exploratory': ['#8a5a00', '<path d="M12 9v4"></path><path d="M12 17h.01"></path><path d="M10.3 3.9 1.8 18a2 2 0 0 0 1.7 3h17a2 2 0 0 0 1.7-3L13.7 3.9a2 2 0 0 0-3.4 0z"></path>'],
    'Not available': ['#4b4f58', '<circle cx="12" cy="12" r="10"></circle><path d="m4.9 4.9 14.2 14.2"></path>'],
    'Question': ['#005ea2', '<circle cx="12" cy="12" r="10"></circle><path d="M9.1 9a3 3 0 0 1 5.8 1c0 2-3 3-3 3"></path><path d="M12 17h.01"></path>'],
  };
  const SOURCE = {'Verified': "Source: the review's standard calculations.", 'Exploratory': 'Source: a one-off query, shown above. Check it before quoting.'};
  const conv = document.querySelector('section[aria-label="Conversation"] > div:nth-of-type(2)');
  const qlist = [...document.querySelectorAll('h2')].find(h => h.textContent.trim() === 'Questions asked in this review').parentElement.querySelector('ol');
  const inp = document.getElementById('q'), btn = inp.form.querySelector('button');
  conv.innerHTML = ''; qlist.innerHTML = '';
  const reveal = el => { el.style.scrollMarginBottom = '130px'; el.scrollIntoView({block: 'nearest'}); return el; };  // clear the guide bar
  const add = h => { conv.insertAdjacentHTML('beforeend', h); return reveal(conv.lastElementChild); };
  const esc = s => s.replace(/[&<>"]/g, c => ({'&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;'}[c]));
  const bubble = (inner, ex) => `<div style="background: ${ex ? '#fff8e6' : '#f4f5f7'};${ex ? ' border: 1px solid #ffd27a;' : ''} border-radius: 2px 12px 12px 12px; padding: 14px 18px; font-size: 15px; line-height: 1.55; display: flex; flex-direction: column; gap: 10px">${inner}</div>`;
  const user = q => { add(`<div style="align-self: flex-end; max-width: 640px; background: #e7f1fb; border-radius: 12px 12px 2px 12px; padding: 12px 16px; font-size: 15px; line-height: 1.5">${esc(q)}</div>`); qlist.insertAdjacentHTML('beforeend', `<li>${esc(q)}</li>`); };
  const answer = (r, el) => {
    const k = KIND[r.label];
    const status = k ? `<div style="display: flex; align-items: center; gap: 8px; font-size: 13px; font-weight: 600; color: ${k[0]}"><svg aria-hidden="true" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="${k[0]}" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round">${k[1]}</svg>${r.label}</div>` : '';
    const src = SOURCE[r.label] ? `<p style="margin: 0; font-size: 13px; color: #4b4f58">${SOURCE[r.label]}</p>` : '';
    const h = `<div style="max-width: 760px; display: flex; flex-direction: column; gap: 10px">${status}${bubble(r.body_html, r.label === 'Exploratory')}${src}</div>`;
    if (el) { el.outerHTML = h; reveal(conv.lastElementChild); } else add(h);
  };
  let busy = false;
  const ask = async (text, context) => {
    if (busy || !(text || context)) return;
    busy = true; inp.disabled = btn.disabled = true;
    user(text || 'You added: ' + context);
    const t0 = Date.now();
    const w = add(`<div style="max-width: 760px">${bubble('<p style="margin: 0; color: #4b4f58">Working<span>...</span> A standard calculation takes 5 to 10 seconds; a one-off query about 30. <span data-s>0</span> s</p>')}</div>`);
    const tick = setInterval(() => { const s = w.querySelector('[data-s]'); if (s) s.textContent = Math.round((Date.now() - t0) / 1000); }, 1000);
    try {
      const r = await (await fetch('/api/ask', {method: 'POST', headers: {'Content-Type': 'application/json'}, body: JSON.stringify({text, context})})).json();
      answer(r, w);
    } catch (e) {
      answer({label: null, body_html: '<p style="margin: 0">One moment. Please ask that again.</p>'}, w);
    }
    clearInterval(tick); busy = false; inp.disabled = btn.disabled = false; inp.value = ''; inp.focus({preventScroll: true}); reveal(inp.form);
  };
  btn.type = 'submit';
  inp.form.addEventListener('submit', e => { e.preventDefault(); ask(inp.value.trim(), null); });
  const p = new URLSearchParams(location.search);
  history.replaceState(null, '', '/ask');  // a ?q= submits once: reload and back navigation see /ask
  (async () => {
    for (const t of await (await fetch('/api/history')).json()) { user(t.question); answer(t); }
    if (p.get('q')) ask(p.get('q').trim(), null);
    else if (p.get('context')) ask('', p.get('context').trim());
  })();
})();
"""


if __name__ == "__main__":
    day = datetime.now(timezone.utc).date().isoformat()
    print(f"Review app on http://{HOST}:{PORT}  traces: raw/{day}-s-<session>-trace.jsonl", flush=True)
    ThreadingHTTPServer((HOST, PORT), Handler).serve_forever()
