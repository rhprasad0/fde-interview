"""Refresh challenge/app/data/cell.json: the workshop page's chart data for the open cell, from the semantic views.

Runs the six statements with the eval harness's SQL helper (the Databricks CLI profile token, so it is a laptop job;
in deployment a Databricks job writes the same shape to S3). Usage: challenge/.venv/bin/python challenge/app/refresh.py
"""

import json
import re
import sys
from datetime import datetime, timezone
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parents[0] / "scripts"))
from eval_harness import _sql  # noqa: E402

CELL = {"component": "HSBD", "series": "1895", "quarter": "FY2026Q1", "as_of": "2026-08-01"}
Q = {
    "cbp_months": "SELECT date_format(effective_month, 'yyyy-MM') AS month, count(*) AS n FROM workforce.semantic.accession "
                  "WHERE agency_subelement_code = 'HSBD' AND occupational_series_code = '1895' "
                  "AND effective_month BETWEEN DATE'2025-09-01' AND DATE'2026-01-01' GROUP BY 1 ORDER BY 1",
    "fema_months": "SELECT date_format(effective_month, 'yyyy-MM') AS month, count(*) AS n FROM workforce.semantic.accession "
                   "WHERE agency_subelement_code = 'HSCB' AND effective_month BETWEEN DATE'2025-09-01' AND DATE'2026-08-01' "
                   "GROUP BY 1 ORDER BY 1",
    "yos": "SELECT bucket, headcount, share FROM workforce.semantic.length_of_service_profile('2026-08-01', 'HSBD', '1895')",
    "separations": "SELECT separation_category AS category, count(*) AS n FROM workforce.semantic.separation "
                   "WHERE agency_subelement_code = 'HSBD' AND occupational_series_code = '1895' "
                   "AND effective_month BETWEEN DATE'2025-09-01' AND DATE'2026-08-01' GROUP BY 1 ORDER BY 2 DESC",
    "states": "SELECT duty_station_state AS state, headcount, headcount_location_imputed AS imputed "
              "FROM workforce.semantic.headcount('2026-08-01', 'HSBD', '1895') ORDER BY headcount DESC",
    "plan": "SELECT planned_hires, actual_accessions, variance, variance_pct FROM workforce.semantic.plan_variance('FY2026Q1', 'HSBD', '1895')",
}


def _rows(body):
    """Statement API results as dicts; the API returns every value as a string."""
    cols = [c["name"] for c in body["manifest"]["schema"]["columns"]]
    num = lambda v: v if v is None or not re.fullmatch(r"-?\d+(\.\d+)?(E-?\d+)?", str(v)) else (int(v) if re.fullmatch(r"-?\d+", v) else float(v))  # noqa: E731
    return [dict(zip(cols, map(num, r))) for r in (body.get("result") or {}).get("data_array") or []]


if __name__ == "__main__":
    out = {"refreshed_at": datetime.now(timezone.utc).isoformat(timespec="seconds"), "cell": CELL}
    for k, sql in Q.items():
        out[k] = _rows(_sql(sql, []))
        print(f"{k}: {len(out[k])} rows", flush=True)
    out["plan"] = out["plan"][0] if out["plan"] else None
    (HERE / "data").mkdir(exist_ok=True)
    (HERE / "data/cell.json").write_text(json.dumps(out, indent=1) + "\n")
    print("wrote data/cell.json")
