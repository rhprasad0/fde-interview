"""Spec 06: build the data layer in DuckDB on the laptop and ship the agent-facing tables to Postgres.

    python scripts/load_postgres.py          # build challenge/data/workforce.duckdb and check the counts
    python scripts/load_postgres.py --ship   # ... then replace the eight tables in Postgres (PG* from challenge/.env)

Reads the files pull_sources.py left under challenge/data; nothing whole-government leaves the laptop.
The views, functions, and roles are Postgres SQL in challenge/sql/*.pg.sql, run with psql afterwards.
"""

import os
import sys
import time
from pathlib import Path

import duckdb

REPO = Path(__file__).resolve().parents[2]
SQL = REPO / "challenge/sql"
for _line in (REPO / "challenge/.env").read_text().splitlines():  # same parse as agent.py
    _k, _sep, _v = _line.split("#", 1)[0].partition("=")
    if _sep:
        os.environ.setdefault(_k.strip(), _v.strip().strip("'\""))

# Draw-independent acceptance numbers from specs/02-results.md and specs/03-results.md.
CHECKS = [
    ("SELECT count(*) FROM bronze.opm_employment WHERE source_file = 'employment_202608_1.parquet'", 2_024_832),
    ("SELECT count(*) FROM bronze.opm_separations WHERE source_file = 'separations_202509_5.parquet'", 120_540),
    ("SELECT count(*) FROM silver.employment", 2_725_190),
    ("SELECT count(*) FROM silver.separations", 27_799),
    ("SELECT count(*) FROM silver.accessions", 25_852),
    ("SELECT count(*) FROM silver.job_postings", 13_136),
    ("SELECT count(DISTINCT control_number) FROM silver.job_postings", 13_136),
    ("SELECT count(*) FROM silver.job_postings WHERE opening_status = 'Accepting applications'", 724),
    ("SELECT count(*) FROM silver.job_postings WHERE agency_level = 1", 43),
    ("SELECT count(*) FROM silver.agency_subelements", 1_072),
    ("SELECT count(*) FROM silver.occupational_series", 822),
    ("SELECT count(*) FROM silver.places", 32_126),
    ("SELECT count(*) FROM silver.state_centroids", 55),
    ("SELECT count(*) FROM synthetic.posting_locations", 27_310),
    ("SELECT count(*) FROM synthetic.posting_pay", 16_913),
    ("SELECT count(*) FROM synthetic.employment", 2_725_190),
    ("SELECT count(*) FROM synthetic.separations", 27_799),
    ("SELECT count(*) FROM synthetic.accessions", 25_852),
    ("SELECT count(*) FROM synthetic.employment WHERE snapshot_month = DATE'2026-08-01' AND pay_redacted", 171_627),
    ("SELECT count(*) FROM synthetic.employment WHERE snapshot_month = DATE'2026-08-01' AND location_imputed", 171_296),
    ("SELECT count(*) FROM synthetic.employment WHERE snapshot_month = DATE'2026-08-01' AND pay_imputed", 162_812),
    ("SELECT count(*) FROM synthetic.employment WHERE (location_imputed OR pay_imputed) AND NOT pay_redacted", 0),
    ("SELECT count(*) FROM synthetic.staffing_plan", 1_680),
    ("SELECT count(DISTINCT (agency_subelement_code, occupational_series_code)) FROM synthetic.staffing_plan", 210),
    ("SELECT planned_hires FROM synthetic.staffing_plan WHERE agency_subelement_code = 'HSBD' AND occupational_series_code = '1895' AND fiscal_quarter = 'FY2026Q1'", 594),
]
# Shipped as-is except the postings' nested columns, which go over as JSON text for Postgres to cast to jsonb.
SHIP = {
    "silver.job_postings": "SELECT * REPLACE (to_json(occupational_series_codes)::VARCHAR AS occupational_series_codes, "
                           "to_json(locations)::VARCHAR AS locations, to_json(hiring_paths)::VARCHAR AS hiring_paths) FROM silver.job_postings",
    # The three fact tables ship sorted by cell so a cell's rows sit in adjacent blocks: unsorted, one cell's 27k rows
    # spanned 23k random reads and overran the 30 s timeout on the micro instance (smoke, 2026-11-02).
    "synthetic.employment": "SELECT * FROM synthetic.employment ORDER BY agency_subelement_code, occupational_series_code, snapshot_month",
    "synthetic.separations": "SELECT * FROM synthetic.separations ORDER BY effective_month, agency_subelement_code, occupational_series_code",
    "synthetic.accessions": "SELECT * FROM synthetic.accessions ORDER BY effective_month, agency_subelement_code, occupational_series_code",
    **{t: f"SELECT * FROM {t}" for t in ("silver.agency_subelements", "silver.occupational_series", "synthetic.staffing_plan",
                                           "synthetic.imputation_quality")},
}


def main(ship: bool) -> None:
    t0 = time.perf_counter()
    con = duckdb.connect(str(REPO / "challenge/data/workforce.duckdb"))
    con.execute(f"SET VARIABLE data = '{REPO / 'challenge/data'}'")
    for f in ("02_load.duckdb.sql", "03_synthetic.duckdb.sql"):
        con.execute((SQL / f).read_text())
        print(f, f"{time.perf_counter() - t0:.0f}s")
    bad = [(sql, got, want) for sql, want in CHECKS if (got := con.execute(sql).fetchone()[0]) != want]
    for sql, got, want in bad:
        print("MISMATCH", got, "!=", want, sql)
    assert not bad, f"{len(bad)} of {len(CHECKS)} checks failed"
    print(f"{len(CHECKS)} checks pass")
    if not ship:
        return
    con.execute("INSTALL postgres; LOAD postgres; ATTACH '' AS pg (TYPE postgres)")  # libpq reads PG* from the environment
    for t, q in SHIP.items():
        con.execute(f"CALL postgres_execute('pg', 'DROP TABLE IF EXISTS {t} CASCADE')")  # CASCADE: the semantic views; 03_semantic.pg.sql recreates them
        con.execute(f"CREATE TABLE pg.{t} AS {q}")
        n = con.execute(f"SELECT * FROM postgres_query('pg', 'SELECT count(*) FROM {t}')").fetchone()[0]  # server-side; the scanner would walk the table
        print(t, n, f"{time.perf_counter() - t0:.0f}s")


if __name__ == "__main__":
    main("--ship" in sys.argv[1:])
