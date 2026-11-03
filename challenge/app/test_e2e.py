"""Browser tests, headless Chromium against the app on a free port, the agent faked so no database or key is needed:
challenge/.venv/bin/python -m pytest challenge/app/test_e2e.py -q   (requirements-dev.txt, then playwright install chromium)
"""

import re
import socket
import threading
import time

import pytest

pw = pytest.importorskip("playwright.sync_api")  # the unit tests still run without the browser
import uvicorn  # noqa: E402

import backend  # noqa: E402
import main  # noqa: E402


async def fake_stream(turns, text, context, session_id):
    yield {"delta": "Ver"}
    yield {"tool": "plan_variance"}
    yield {"done": {"answer_text": "Verified\n475 onboarded against **594** planned.", "error": None, "cited_tools": ["plan_variance"],
                    "latency_ms": 1200, "cost_usd": 0.001, "question_text": text}}


@pytest.fixture(scope="module")
def base_url():
    mp = pytest.MonkeyPatch()
    mp.setattr(backend, "stream", fake_stream)  # main.ask looks backend.stream up per request, so the patch applies in-process
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        port = s.getsockname()[1]
    server = uvicorn.Server(uvicorn.Config(main.app, host="127.0.0.1", port=port, log_level="warning"))
    threading.Thread(target=server.run, daemon=True).start()  # off the main thread uvicorn skips signal handling
    for _ in range(200):
        if server.started:
            break
        time.sleep(0.05)
    assert server.started
    yield f"http://127.0.0.1:{port}"
    server.should_exit = True
    mp.undo()


@pytest.fixture(scope="module")
def page(base_url):
    with pw.sync_playwright() as p:
        browser = p.chromium.launch()
        pg = browser.new_page()
        pg.set_default_timeout(10_000)
        yield pg
        browser.close()


def test_health(base_url, page):
    assert page.request.get(base_url + "/health").json() == {"ok": True}


def test_workshop_renders_the_cell_and_the_nav(base_url, page):
    page.goto(base_url + "/")
    pw.expect(page.locator("#thread")).to_be_visible()
    pw.expect(page.locator("nav.tabs a", has_text="Field notes")).to_have_attribute("href", "/study")


def test_evals_leads_with_the_headline_pair(base_url, page):
    page.goto(base_url + "/evals")
    pw.expect(page.locator("#h1")).to_contain_text("held-out questions pass")
    pw.expect(page.locator("#t-pk")).to_have_text(re.compile(r"^\d+ / \d+$"))
    pw.expect(page.locator("#story-t tbody tr")).to_have_count(len(main.evals.MILESTONES))
    pw.expect(page.locator("#heat svg text", has_text=re.compile(r"^10$"))).to_have_count(1)
    d = page.request.get(base_url + "/api/evals").json()
    assert page.locator("#heat svg rect").count() == d["headline"]["rows"]


@pytest.mark.parametrize("path,tab,h1", [("/study", "Field notes", "One tester"), ("/mission", "Mission", "Over 80 agencies"), ("/incident", "Incident report", "pick up Databricks")])
def test_static_pages_render(base_url, page, path, tab, h1):
    page.goto(base_url + path)
    pw.expect(page.locator("h1")).to_contain_text(h1)
    pw.expect(page.locator("nav.tabs a[aria-current]")).to_have_text(tab)
    pw.expect(page.locator("main table tbody tr").first).to_be_visible()


def test_ask_streams_a_labelled_answer(base_url, page):
    page.goto(base_url + "/")
    page.fill("#q", "How many onboarded?")
    page.click("#askbtn")
    pw.expect(page.locator(".msg.bot .chip").last).to_have_text("Verified")
    pw.expect(page.locator(".msg.bot .bub strong").last).to_have_text("594")
    pw.expect(page.locator("#askbtn")).to_be_enabled()
