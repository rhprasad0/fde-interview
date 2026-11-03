"""Genie benchmarks: the eval set's Genie-tier rows asked of Genie directly, with no agent in between.

  genie_bench.py sync                 benchmarks from questions.yaml into challenge/genie/dhs-workforce.json; push the space
  genie_bench.py run [--note TEXT]    start an eval run, wait, append one line per question to challenge/eval/genie-bench.jsonl
  genie_bench.py report [run ...]     per-question GOOD counts across runs (default: every run of the current space hash)
  genie_bench.py calibrate            both graders against the hand labels in challenge/eval/genie-labels.jsonl

Runs as Ryan's user (databricks CLI, profile workforce), who owns the space. Each run is tagged with the space hash, a
hash of the space configuration without its benchmarks, so a Genie experiment shows as a new hash the way a prompt
change does in the agent eval. Benchmarks are never used as context.

Two verdicts per question. `native` is Genie's own result-set comparison, which fails a correct answer on shape (a
month as a DATE where truth has 'yyyy-MM', every city where truth keeps the top ten). `pass` grades Genie's returned
rows with the agent eval's scorers (numeric_match, list_match with key_by), so the two paths are comparable: a number
row passes when some numeric cell matches truth; a list row when some key column and value column match it.
"""

import argparse
import hashlib
import json
import subprocess
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

import yaml

import eval_harness as H  # noqa: E402  (the agent eval's scorers and merged truth)

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "prototype"))
import agent as A  # noqa: E402  (REPO, SPACE, redact)

SPACE_JSON = A.REPO / "challenge/genie/dhs-workforce.json"
QUESTIONS = A.REPO / "challenge/eval/questions.yaml"
RESULTS = A.REPO / "challenge/eval/genie-bench.jsonl"
LABELS = A.REPO / "challenge/eval/genie-labels.jsonl"  # one hand label per (run, question): is Genie's answer right
DONE = {"DONE", "EVALUATION_FAILED", "EVALUATION_CANCELLED", "EVALUATION_TIMEOUT"}


def _cli(*args, body=None):
    """One databricks CLI call as JSON; errors are raised with ids redacted."""
    cmd = ["databricks", *args, "-p", "workforce", "-o", "json"] + (["--json", json.dumps(body)] if body is not None else [])
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode != 0:
        raise RuntimeError(A.redact(f"{' '.join(args[:2])}: {r.stderr.strip()[:600]}"))
    return json.loads(r.stdout) if r.stdout.strip() else {}


def bench_id(qid):
    """Stable 32-hex id per question, so results map back to the eval row without a lookup file."""
    return hashlib.md5(f"benchmark:{qid}".encode()).hexdigest()


def space_hash(space):
    return hashlib.sha256(json.dumps({k: v for k, v in space.items() if k != "benchmarks"}, sort_keys=True).encode()).hexdigest()[:8]


def benchmarks():
    """Genie-tier rows that carry truth SQL. Narrative rows (truth_facts only) are left out: Genie grades result sets."""
    qs = yaml.safe_load(QUESTIONS.read_text())["questions"]
    rows = [q for q in qs if q["tier"] == "genie" and q.get("truth_sql")]
    out = [{"id": bench_id(q["id"]), "question": [q["verbatim"]],
            "answer": [{"format": "SQL", "content": [line + "\n" for line in q["truth_sql"].strip().splitlines()]}]}
           for q in rows]
    return sorted(out, key=lambda b: b["id"]), {bench_id(q["id"]): q["id"] for q in rows}


def _live():
    return json.loads(_cli("genie", "get-space", A.SPACE, "--include-serialized-space").get("serialized_space") or "{}")


def sync(force=False):
    """Full replacement of the space from the repo JSON. Refuses when the live space differs from the repo outside its
    benchmarks (an edit made in the UI would be lost), unless forced."""
    space = json.loads(SPACE_JSON.read_text())
    live, norm = _live(), (lambda d: json.dumps({k: v for k, v in d.items() if k != "benchmarks"}, sort_keys=True))
    if norm(live) != norm(space) and not force:
        diff = sorted(k for k in set(live) | set(space) if k != "benchmarks" and json.dumps(live.get(k), sort_keys=True)
                      != json.dumps(space.get(k), sort_keys=True))
        raise SystemExit(f"live space differs from {SPACE_JSON.name} in {diff}; copy the change into the repo, or --force")
    space["benchmarks"] = {"questions": benchmarks()[0]}
    SPACE_JSON.write_text(json.dumps(space, indent=2) + "\n")
    _cli("genie", "update-space", A.SPACE, body={"serialized_space": json.dumps(space)})
    live = _live()
    got = {b["id"] for b in (live.get("benchmarks") or {}).get("questions") or []}
    want = {b["id"] for b in space["benchmarks"]["questions"]}
    if got != want:
        raise SystemExit(f"space has {len(got)} benchmarks, expected {len(want)}; missing {len(want - got)}")
    print(f"space {space_hash(space)}: {len(want)} benchmarks live")


def _pages(path):
    items, token = [], None
    while True:
        r = _cli("api", "get", path + (f"?page_size=100&page_token={token}" if token else "?page_size=100"))
        items += r.get("eval_results") or r.get("eval_runs") or []
        token = r.get("next_page_token")
        if not token:
            return items


def _num(v):
    try:
        return float(v)
    except (TypeError, ValueError):
        return None


def _scales(q):
    """A rate stated as a percent is the same answer: when truth is a fraction, also try the value over 100."""
    t = q.get("truth_value")
    vals = [t] if not isinstance(t, list) else [x.get("value") for x in t]
    return (1, 100) if all(isinstance(v, (int, float)) and abs(v) <= 1 for v in vals) else (1,)


def grade(q, detail):
    """(pass, how) for Genie's returned rows, judged by the agent eval's own scorers. Only the format of a correct answer
    is forgiven (which columns, long or wide, percent or fraction); its values must still match truth."""
    ser = ((detail.get("actual_response") or [{}])[0]).get("sql_execution_result") or {}
    cols = [c["name"] for c in ((ser.get("manifest") or {}).get("schema") or {}).get("columns") or []]
    rows = [[(v or {}).get("str") for v in r.get("values") or []] for r in (ser.get("result") or {}).get("data_typed_array") or []]
    if not rows:
        return False, "no rows"
    for scale in _scales(q):
        sv = lambda v: None if _num(v) is None else _num(v) / scale  # noqa: E731
        if q["expected_behavior"] == "number":
            for i, c in enumerate(cols):
                if any(sv(r[i]) is not None and H.numeric_match(q, {"answer_value": sv(r[i])}) for r in rows):
                    return True, f"{c}" + (" (percent)" if scale == 100 else "")
            continue
        numeric = [i for i in range(len(cols)) if all(_num(r[i]) is not None for r in rows if r[i] is not None)]
        for k in range(len(cols)):  # long: one key column, one value column
            for v in numeric:
                if v != k and H.list_match(q, {"answer_value": [{"key": r[k], "value": sv(r[v])} for r in rows]}):
                    return True, f"{cols[k]} / {cols[v]}" + (" (percent)" if scale == 100 else "")
        for r in rows:  # wide: one row whose columns are the figures; the first column for each key counts
            seen, av = set(), []
            for i in numeric:
                key = H._key(cols[i], q.get("key_by"))
                if key not in seen and sv(r[i]) is not None:
                    seen.add(key); av.append({"key": cols[i], "value": sv(r[i])})
            if av and H.list_match(q, {"answer_value": av}):
                return True, "wide row " + ", ".join(x["key"] for x in av[:3]) + (" (percent)" if scale == 100 else "")
    return False, "no key and value columns match"


def run(note=None, timeout_s=1800):
    space = json.loads(SPACE_JSON.read_text())
    sh, ids = space_hash(space), benchmarks()[1]
    base = f"/api/2.0/genie/spaces/{A.SPACE}/eval-runs"
    started = datetime.now(timezone.utc)
    ev = _cli("api", "post", base, body={})
    rid = ev["eval_run_id"]
    print(f"eval run started, space {sh}, {ev.get('num_questions')} questions")
    deadline = time.monotonic() + timeout_s
    while ev.get("eval_run_status") not in DONE and time.monotonic() < deadline:
        time.sleep(15)
        ev = _cli("api", "get", f"{base}/{rid}")
    if ev.get("eval_run_status") != "DONE":
        raise SystemExit(f"eval run ended {ev.get('eval_run_status')} after {(time.monotonic() - deadline + timeout_s):.0f}s")
    run_id = f"{started:%Y%m%dT%H%M%SZ}-{sh}"
    _, qs = H._questions()
    lines = []
    for res in _pages(f"{base}/{rid}/results"):
        d = _cli("api", "get", f"{base}/{rid}/results/{res['result_id']}")
        qid = ids.get(res["benchmark_question_id"])
        ok, how = grade(qs[qid], d) if qid in qs else (False, "unknown question")
        lines.append({"genie_run_id": run_id, "space_hash": sh, "note": note, "q_id": qid, "pass": ok, "pass_how": how,
                      "status": res.get("status"), "assessment": d.get("assessment"),
                      "manual_assessment": d.get("manual_assessment"), "reasons": d.get("assessment_reasons"),
                      "detail": {k: v for k, v in d.items() if k not in ("result_id", "space_id", "benchmark_question_id",
                                                                         "assessment", "assessment_reasons")}})
    with RESULTS.open("a") as f:
        for line in lines:
            f.write(A.redact(json.dumps(line, default=str)) + "\n")
    print(f"took {(datetime.now(timezone.utc) - started).total_seconds() / 60:.1f} min")
    print(f"{run_id}: pass {sum(x['pass'] for x in lines)}/{len(lines)} by the eval's scorers; "
          f"Genie's own grader GOOD {sum(x['assessment'] == 'GOOD' for x in lines)}/{len(lines)}")
    for x in sorted(lines, key=lambda x: x["q_id"] or ""):
        print(f"  {x['q_id']} {'PASS' if x['pass'] else 'fail'} ({x['pass_how']}) | native {x['assessment']} "
              f"{'; '.join(x['reasons'] or [])[:90]}")
    return run_id


def report(runs=None):
    """Pooled passes per question over runs, graded now from the stored rows against the current truth."""
    _, qs = H._questions()
    rows = [json.loads(x) for x in RESULTS.read_text().splitlines()] if RESULTS.exists() else []
    if not runs:
        sh = space_hash(json.loads(SPACE_JSON.read_text()))
        runs = sorted({r["genie_run_id"] for r in rows if r["space_hash"] == sh})
    per = {}
    for r in rows:
        if r["genie_run_id"] in runs and r["q_id"] in qs:
            c = per.setdefault(r["q_id"], [0, 0, 0])
            c[0] += grade(qs[r["q_id"]], r["detail"])[0]; c[1] += r["assessment"] == "GOOD"; c[2] += 1
    n = sum(c[2] for c in per.values())
    print(f"{len(runs)} runs: pooled pass {sum(c[0] for c in per.values())}/{n} by the eval's scorers, "
          f"Genie GOOD {sum(c[1] for c in per.values())}/{n}")
    for qid in sorted(per):
        print(f"  {qid} pass {per[qid][0]}/{per[qid][2]}  native GOOD {per[qid][1]}/{per[qid][2]}")


def calibrate():
    """Each grader against the hand labels: agreement, false passes (graded right, labelled wrong), false fails."""
    _, qs = H._questions()
    results = {(r["genie_run_id"], r["q_id"]): r for r in map(json.loads, RESULTS.read_text().splitlines())}
    labels = [json.loads(x) for x in LABELS.read_text().splitlines()]
    tally = {"eval scorers": [0, 0, 0], "Genie's grader": [0, 0, 0]}  # agree, false pass, false fail
    misses = []
    for lab in labels:
        r = results.get((lab["genie_run_id"], lab["q_id"]))
        if r is None:
            continue
        for name, verdict in (("eval scorers", grade(qs[lab["q_id"]], r["detail"])[0]), ("Genie's grader", r["assessment"] == "GOOD")):
            t = tally[name]
            if verdict == lab["correct"]:
                t[0] += 1
            else:
                t[1 if verdict else 2] += 1
                misses.append(f"  {name}: {lab['q_id']} {lab['genie_run_id'][:16]} graded {'pass' if verdict else 'fail'}, "
                              f"labelled {'right' if lab['correct'] else 'wrong'} ({lab['note']})")
    n = sum(1 for lab in labels if (lab["genie_run_id"], lab["q_id"]) in results)
    confirmed = sum(1 for lab in labels if lab.get("confirmed_by"))
    print(f"{n} labelled results ({confirmed} confirmed by a person), {sum(lab['correct'] for lab in labels)} right")
    for name, (agree, fp, ff) in tally.items():
        print(f"{name}: agrees {agree}/{n}, false passes {fp}, false fails {ff}")
    print("\n".join(misses) or "  no disagreements")


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("cmd", choices=["sync", "run", "report", "calibrate"])
    ap.add_argument("runs", nargs="*")
    ap.add_argument("--note")
    ap.add_argument("--force", action="store_true", help="sync: replace the space even if it was edited outside the repo")
    a = ap.parse_args()
    {"sync": lambda: sync(a.force), "run": lambda: run(a.note), "report": lambda: report(a.runs), "calibrate": calibrate}[a.cmd]()
