"""No network: challenge/.venv/bin/python -m pytest challenge/app/test_app.py -q"""

import asyncio
import json

import pytest

import backend
import evals
import main


def test_turns_rejects_blank_and_bad_roles():
    assert backend.messages([{"role": "user", "text": "hi"}, {"role": "assistant", "text": "Verified\nyes"}]) == [
        {"role": "user", "content": [{"text": "hi"}]}, {"role": "assistant", "content": [{"text": "Verified\nyes"}]}]
    with pytest.raises(ValueError):
        backend.messages([{"role": "user", "text": "  "}])
    with pytest.raises(ValueError):
        backend.messages([{"role": "system", "text": "x"}])


def _frames(events):
    async def collect():
        return [json.loads(f.removeprefix("data: ")) async for f in main.sse(events)]
    return asyncio.run(collect())


def test_sse_ends_with_exactly_one_done_and_renders_the_label():
    async def ok():
        yield {"delta": "Ver"}
        yield {"tool": "plan_variance"}
        yield {"done": {"answer_text": "Verified\n475 against **594**.", "error": None}}
    out = _frames(ok())
    assert [list(f)[0] for f in out] == ["delta", "tool", "done"]
    assert out[-1]["done"]["label"] == "Verified" and "<strong>594</strong>" in out[-1]["done"]["body_html"]

    async def boom():
        yield {"delta": "x"}
        raise RuntimeError("mcp fell over")
    out = _frames(boom())
    assert sum("done" in f for f in out) == 1 and out[-1]["done"]["error"] == "agent"


def test_evals_shape(tmp_path):
    (tmp_path / "q.yaml").write_text("set_version: t\nquestions:\n- id: C01\n  tier: verified\n  verbatim: one\n- id: C02\n  tier: genie\n  verbatim: two\n")
    (tmp_path / "t.json").write_text(json.dumps({"C02": {"truth_value": [{"key": "a", "value": 1}]}}))
    rows = [{"experiment_id": "20261102T100000Z-aaaa", "id": "C01", "run_index": 1, "pass": True, "cost_usd": .01, "latency_ms": 1000},
            {"experiment_id": "20261102T100000Z-aaaa", "id": "C02", "run_index": 1, "pass": False, "failure_category": "list_match",
             "genie_sql": "SELECT 1", "cost_usd": .02, "latency_ms": 3000, "list_match": False, "label_match": True},
            {"experiment_id": "20261102T100000Z-aaaa", "id": "C02", "run_index": 2, "pass": True, "cost_usd": .02, "latency_ms": 2000}]
    (tmp_path / "e.jsonl").write_text("\n".join(json.dumps(r) for r in rows) + "\n")
    d = evals.load(tmp_path / "e.jsonl", tmp_path / "q.yaml", tmp_path / "t.json")
    e = d["experiments"][0]
    assert e["label"] == "100000Z" and e["prompt"] == "aaaa" and e["runs"] == 2 and e["passk"] == 1 and e["questions"] == 2
    assert e["pass1"] == {"Verified": [1, 1], "Exploratory": [1, 2]} and e["latency_p50_s"] == 2
    assert d["failures"] == {"list_match": 1} and d["spend_usd"] == 0.05
    assert [r["category"] for r in d["grid"][1]["runs"]] == ["list_match", None]
    assert d["trace"]["id"] == "C02" and d["trace"]["scorers"] == {"label_match": True, "list_match": False}
    assert d["trace"]["truth_value"][0]["key"] == "a"
