"""The eval dashboard's data: challenge/eval/experiments.jsonl read into one JSON document.

The tier tally mirrors eval_harness.pool's tally; it is repeated here because importing the harness pulls in the agent,
git, and the judge clients, which a page load should not do.

No row says which set or arm an experiment belongs to: the as-written and corrected held-out runs share prompt hash
and question ids, and the smoke rows are unmarked. MILESTONES names them by experiment id; the one flagged headline is
the pair the heatmap and the debug rail open on. The sets, judges and effort per experiment are in the eval journal.
"""

import json
import math
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

_P = "20261103T{}-b44a9181"
MILESTONES = [  # journal.md: "After the plateau", "Held-out line", "Held-out rerun", "Agent effort sweep"
    {"name": "Final dev prompt, the 20 rows it was tuned against", "ids": [_P.format("155440Z"), _P.format("155658Z")]},
    {"name": "Held-out, the tester's 8 rows as first written", "ids": [_P.format("170036Z"), _P.format("170419Z")]},
    {"name": "Held-out, six rows corrected by Ryan, rerun beside", "ids": [_P.format("172209Z"), _P.format("172735Z")]},
    {"name": "Sweep at cap 16000, high (stopped: the cap was being measured)", "ids": [_P.format("190755Z"), _P.format("191253Z")]},
    {"name": "Sweep at cap 16000, xhigh (stopped)", "ids": [_P.format("191926Z"), _P.format("192638Z")]},
    {"name": "Sweep at cap 64000, high", "ids": [_P.format("193405Z"), _P.format("193928Z")]},
    {"name": "Sweep at cap 64000, xhigh: the shipped configuration", "ids": [_P.format("194449Z"), _P.format("195233Z")], "headline": True},
    {"name": "Sweep at cap 64000, max", "ids": [_P.format("195932Z"), _P.format("202031Z")]},
]


def wilson(k: int, n: int, z: float = 1.96) -> list[float]:
    """95% Wilson score interval for k of n, as [lo, hi]; [0, 0] when n is 0."""
    if not n:
        return [0.0, 0.0]
    p, d = k / n, 1 + z * z / n
    c, h = (p + z * z / (2 * n)) / d, z * math.sqrt(p * (1 - p) / n + z * z / (4 * n * n)) / d
    return [round(c - h, 3), round(c + h, 3)]


def _tally(rows, qs):
    line = {}
    for r in rows:
        t = line.setdefault(TIER.get(qs[r["id"]]["tier"], qs[r["id"]]["tier"]), [0, 0])
        t[0] += bool(r["pass"])
        t[1] += 1
    return line


def _passk(rows):
    """(questions that passed every run, questions, runs per question)."""
    per = {}
    for r in rows:
        per.setdefault(r["id"], []).append(bool(r["pass"]))
    return sum(all(v) for v in per.values()), len(per), max((len(v) for v in per.values()), default=0)


def _summary(exp: str, rs: list, qs: dict) -> dict:
    passk, questions, runs = _passk(rs)
    return {
        "id": exp, "label": exp[9:16], "prompt": exp.split("-")[-1], "sha": (rs[0].get("agent_git_sha") or "")[:7],
        "run_at": rs[0].get("run_at"), "rows": len(rs), "runs": runs, "questions": questions, "passk": passk,
        "pass1": _tally(rs, qs), "cost_usd": round(sum(r.get("cost_usd") or 0 for r in rs), 4),
        "latency_p50_s": round(statistics.median(r.get("latency_ms") or 0 for r in rs) / 1000),
        "errors": sum(1 for r in rs if r.get("error")),
        "set": "dev" if rs[0]["id"].startswith("C") else "held-out",
        "judge": "xhigh" if any(r.get("judge_effort") for r in rs) else "old",  # set only on judged rows
        "effort": rs[0].get("effort") or "high", "max_tokens": rs[0].get("max_tokens") or 16000,  # the defaults before the sweep
        "truncated": sum("max_tokens" in str(r.get("error") or "") for r in rs),
    }


def load(experiments: Path = EXPERIMENTS, questions: Path = QUESTIONS, truth: Path = TRUTH, milestones=MILESTONES) -> dict:
    qs = {q["id"]: q for q in yaml.safe_load(questions.read_text())["questions"]}
    tv = json.loads(truth.read_text()) if truth.exists() else {}
    rows = [json.loads(x) for x in experiments.read_text().splitlines() if x.strip()]
    rows = [r for r in rows if r["id"] in qs]
    by = {}
    for r in rows:  # file order is time order; the harness appends
        by.setdefault(r["experiment_id"], []).append(r)
    exps = [_summary(exp, rs, qs) for exp, rs in by.items()]
    latest = exps[-1]["id"] if exps else None

    def pair(ids):
        """The experiments of one milestone as one row list, run_index offset so the second's runs follow the first's."""
        out, offset = [], 0
        for i in ids:
            out += [{**r, "run_index": r["run_index"] + offset} for r in by[i]]
            offset += _passk(by[i])[2]
        return out

    ms = []
    for m in milestones:
        if not all(i in by for i in m["ids"]):
            continue
        rs = pair(m["ids"])
        s, (k, q, n) = _summary("+".join(m["ids"]), rs, qs), _passk(rs)
        ms.append({"name": m["name"], "ids": m["ids"], "headline": bool(m.get("headline")),
                   **{f: s[f] for f in ("set", "judge", "effort", "max_tokens", "truncated", "cost_usd", "latency_p50_s")},
                   "pass1": [sum(bool(r["pass"]) for r in rs), len(rs)],
                   "passk_each": [list(_passk(by[i])) for i in m["ids"]], "passk_pair": [k, q, n], "wilson": wilson(k, q)})
    head = next((m for m in ms if m["headline"]), None)
    hids = head["ids"] if head else [latest] if latest else []
    hrows = pair(hids) if hids else []
    headline = {**_summary("+".join(hids), hrows, qs), "ids": hids} if hrows else None
    if headline:
        headline["wilson"] = wilson(headline["passk"], headline["questions"])

    grid = []
    for qid in sorted({r["id"] for r in hrows}):
        q, runs = qs[qid], sorted((r for r in hrows if r["id"] == qid), key=lambda r: r["run_index"])
        grid.append({"id": qid, "tier": TIER.get(q["tier"], q["tier"]), "class": q.get("class"), "text": q.get("verbatim") or "",
                     "runs": [{"pass": bool(r["pass"]), "category": None if r["pass"] else r.get("failure_category"),
                               "latency_s": round((r.get("latency_ms") or 0) / 1000)} for r in runs]})
    failing = [r for r in hrows if not r["pass"]]
    trace = next((r for r in failing if r.get("failure_category") == "list_match" and r.get("genie_sql")), failing[0] if failing else None)
    return {
        "experiments": exps, "latest": latest, "headline": headline, "milestones": ms, "grid": grid,
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
