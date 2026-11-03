"""The eval dashboard's data: challenge/eval/experiments.jsonl read into one JSON document.

The tier tally mirrors eval_harness.pool's tally; it is repeated here because importing the harness pulls in the agent,
git, and the judge clients, which a page load should not do.
"""

import json
import statistics
from collections import Counter
from pathlib import Path

import yaml

REPO = Path(__file__).resolve().parents[2]
EXPERIMENTS = REPO / "challenge/eval/experiments.jsonl"
QUESTIONS = REPO / "challenge/eval/questions.yaml"
TRUTH = REPO / "challenge/eval/truth.json"
TIER = {"verified": "Verified", "genie": "Exploratory", "refusal": "Not available"}
SCORERS = ("label_match", "numeric_match", "list_match", "labels_present", "tool_use", "provenance", "genie_sql_stored",
           "refusal", "data_limit", "limit_stated", "reading_stated", "faithfulness", "assumption_labeled", "assumption_stated")


def _tally(rows, qs):
    line = {}
    for r in rows:
        t = line.setdefault(TIER.get(qs[r["id"]]["tier"], qs[r["id"]]["tier"]), [0, 0])
        t[0] += bool(r["pass"])
        t[1] += 1
    return line


def load(experiments: Path = EXPERIMENTS, questions: Path = QUESTIONS, truth: Path = TRUTH) -> dict:
    qs = {q["id"]: q for q in yaml.safe_load(questions.read_text())["questions"]}
    tv = json.loads(truth.read_text()) if truth.exists() else {}
    rows = [json.loads(x) for x in experiments.read_text().splitlines() if x.strip()]
    rows = [r for r in rows if r["id"] in qs]
    by = {}
    for r in rows:  # file order is time order; the harness appends
        by.setdefault(r["experiment_id"], []).append(r)
    exps = []
    for exp, rs in by.items():
        per = {}
        for r in rs:
            per.setdefault(r["id"], []).append(bool(r["pass"]))
        exps.append({
            "id": exp, "label": exp[9:16], "prompt": exp.split("-")[-1], "sha": (rs[0].get("agent_git_sha") or "")[:7],
            "run_at": rs[0].get("run_at"), "rows": len(rs), "runs": max(len(v) for v in per.values()),
            "pass1": _tally(rs, qs), "passk": sum(all(v) for v in per.values()), "questions": len(per),
            "cost_usd": round(sum(r.get("cost_usd") or 0 for r in rs), 4),
            "latency_p50_s": round(statistics.median(r.get("latency_ms") or 0 for r in rs) / 1000),
            "errors": sum(1 for r in rs if r.get("error")),
        })
    latest = exps[-1]["id"] if exps else None
    lrows = by.get(latest, [])
    grid = []
    for qid in sorted({r["id"] for r in lrows}):
        q, runs = qs[qid], sorted((r for r in lrows if r["id"] == qid), key=lambda r: r["run_index"])
        grid.append({"id": qid, "tier": TIER.get(q["tier"], q["tier"]), "class": q.get("class"), "text": q.get("verbatim") or "",
                     "runs": [{"pass": bool(r["pass"]), "category": None if r["pass"] else r.get("failure_category"),
                               "latency_s": round((r.get("latency_ms") or 0) / 1000)} for r in runs]})
    failing = [r for r in lrows if not r["pass"]]
    trace = next((r for r in failing if r.get("failure_category") == "list_match" and r.get("genie_sql")), failing[0] if failing else None)
    return {
        "experiments": exps, "latest": latest, "grid": grid,
        "failures": dict(Counter(r.get("failure_category") or "unknown" for r in failing)),
        "spend_usd": round(sum(r.get("cost_usd") or 0 for r in rows), 2), "rows": len(rows),
        "trace": trace and {
            "id": trace["id"], "run_index": trace["run_index"], "tier": TIER.get(qs[trace["id"]]["tier"]), "class": qs[trace["id"]].get("class"),
            "author": qs[trace["id"]].get("author"), "question": trace.get("question_text"), "label": trace.get("label"),
            "answer_text": trace.get("answer_text"), "answer_value": trace.get("answer_value"), "genie_sql": trace.get("genie_sql"),
            "failure_category": trace.get("failure_category"), "latency_ms": trace.get("latency_ms"), "cost_usd": trace.get("cost_usd"),
            "output_tokens": trace.get("output_tokens"), "tool_calls": [{"name": c.get("name"), "rows": c.get("result_rows"),
                                                                        "duration_ms": c.get("duration_ms")} for c in trace.get("tool_calls") or []],
            "scorers": {s: trace.get(s) for s in SCORERS if s in trace}, "truth_value": tv.get(trace["id"], {}).get("truth_value"),
        },
    }
