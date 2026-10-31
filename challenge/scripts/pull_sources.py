"""Spec 02, step 1: one-time pull of the source files to challenge/data/ (gitignored).

Upload afterwards with `databricks fs cp -r` (spec 02, step 2). No key is needed: OPM FWD is
open and the USAJOBS Historic JOA only wants a User-Agent header.

    python scripts/pull_sources.py                 # everything
    python scripts/pull_sources.py separations joa # a subset, by name
"""

import json
import pathlib
import sys

import httpx

OUT = pathlib.Path(__file__).resolve().parents[1] / "data"
OPM = "https://data.opm.gov/api/v1/files"
USAJOBS = "https://data.usajobs.gov"
UA = {"User-Agent": "workforce-agent/0.1"}  # Akamai answers 403 without one
# Twelve months ending at the latest published month (September 2026 is due 2026-11-04).
MONTHS = [f"2025{m:02d}" for m in range(9, 13)] + [f"2026{m:02d}" for m in range(1, 9)]
# Announcements opened from the start of the OPM window to the day of the pull.
JOA_OPEN_FROM, JOA_OPEN_TO = "2025-09-01", "2026-10-31"

client = httpx.Client(timeout=300, follow_redirects=True)


def ndjson(path, rows):
    path.write_text("".join(json.dumps(r) + "\n" for r in rows))
    print(path.relative_to(OUT), len(rows), "rows")


def opm(dataset):
    # Versions differ per dataset and month (June 2026 is v3 employment, v4 separations), so
    # read them from the list endpoint instead of constructing them.
    files = {
        f"{f['year']}{f['month']}": f
        for year in (2025, 2026)
        for f in client.get(f"{OPM}/{dataset}", params={"current": "true", "year": year}).json()
    }
    missing = [m for m in MONTHS if m not in files]
    assert not missing, f"{dataset}: no current file for {missing}"
    out = OUT / "opm" / dataset
    out.mkdir(parents=True, exist_ok=True)
    for m in MONTHS:
        f = files[m]
        path = out / f"{f['filename']}.parquet"
        if path.exists():
            continue
        with client.stream("GET", f"{OPM}/{dataset}/{f['year']}/{f['month']}/{f['version']}/download") as r:
            r.raise_for_status()
            with path.open("wb") as fh:
                for chunk in r.iter_bytes():
                    fh.write(chunk)
        print(path.relative_to(OUT), f"{path.stat().st_size / 1e6:.1f} MB")


def joa():
    out = OUT / "usajobs" / "historicjoa"
    out.mkdir(parents=True, exist_ok=True)
    url = (f"{USAJOBS}/api/historicjoa?HiringDepartmentCodes=HS"
           f"&StartPositionOpenDate={JOA_OPEN_FROM}&EndPositionOpenDate={JOA_OPEN_TO}")
    page, rows, total = 0, 0, None
    while url:
        body = client.get(url, headers=UA).raise_for_status().json()
        page += 1
        ndjson(out / f"page_{page:03d}.json", body["data"])
        rows += len(body["data"])
        paging = body.get("paging", {})  # absent on the last page
        total = total or paging["metadata"]["totalCount"]
        url = USAJOBS + paging["next"] if paging.get("next") else None
    assert rows == total, f"historicjoa: got {rows} rows, API says {total}"


def codelists():
    out = OUT / "usajobs" / "codelist"
    out.mkdir(parents=True, exist_ok=True)
    for name in ("agencysubelements", "occupationalseries"):
        body = client.get(f"{USAJOBS}/api/codelist/{name}", headers=UA).raise_for_status().json()
        ndjson(out / f"{name}.json", body["CodeList"][0]["ValidValue"])


STEPS = {
    "employment": lambda: opm("employment"),
    "separations": lambda: opm("separations"),
    "accessions": lambda: opm("accessions"),
    "joa": joa,
    "codelists": codelists,
}

if __name__ == "__main__":
    for name in sys.argv[1:] or STEPS:
        STEPS[name]()
