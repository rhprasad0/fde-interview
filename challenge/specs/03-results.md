# Spec 03 results

Executed 2026-10-31. Redacted per the Rule: host is `<workspace>`, user is `<user>`, and the
warehouse id and Genie space id stay in `.env`. Spec: [03-semantic-layer.md](03-semantic-layer.md).

## Summary

Every exact number in step 7 matched on the first full build: 171,296 location-imputed and
162,812 pay-imputed August rows, 210 plan cells, TSA 1802 over 12 files, and CBP 1895 FY2026 Q1
at −20.0%. Three job runs gave the same determinism hash. Before the job existed, the notebook
was built cell by cell through the SQL Statement API, and that ad-hoc build gave the same hash too.
Eight functions are visible over MCP as the service principal, and Genie answers the done-when
question by calling the trusted `headcount` function. Things that differ from the spec:

1. **Date parameters are STRING, not DATE.** Genie refused the space at question time: `Invalid
   certified answer function ... argument type is not supported: date`. The six date parameters are
   now `STRING` (`YYYY-MM-DD`), with `to_date()` applied inside the function. MCP was already sending strings, so
   the agent's calls do not change.
2. **The Genie space is created from a file, not in the UI.** `databricks genie create-space` takes
   `challenge/genie/dhs-workforce.json`, which holds the eight views, the six instruction lines, and
   the eight functions. The file is committed and contains no ids. `CAN_RUN` for `workforce-agent`
   goes through the permissions API.
3. **The suffix strip applies to the gazetteer only.** The spec says to normalize
   `duty_station_city` "the same" way, but stripping a trailing ` CITY` turns OPM's `KANSAS CITY`
   into `KANSAS`. So `silver.places` strips the legal suffix, and `synthetic.place_key` (borough tail
   `NEW YORK - KINGS`, apostrophes, periods, `ST` to `SAINT`) runs on both sides.
4. **Geocoding is the last stage of the draw statement**, not a separate pass over the finished
   table. The result is the same, and it needs one statement per table instead of two.
5. **The gazetteer has no BOM.** The local file starts with `USPS`, and `read_files` returns
   `USPS` (hex `55535053`).
6. **There are 55 state centroids, not about 56.** The places file covers the 50 states, DC, and PR
   (52). Guam, the Virgin Islands, and the Northern Marianas have no places, but 889 imputed rows
   sit there. They get a hand-entered island point (three literal rows, `places = 0`), so no row
   with a usable state lacks a point.

**Finding worth knowing before the demo: imputed TSA screeners lead in Alaska.** For TSA 1802 in
August 2026, `headcount` ranks Alaska 3,053, California 2,512, New York 1,784, and Colorado 1,741.
Every one of these rows is imputed, because OPM redacts all of TSA's locations. The pool causes
this. TSA posted 76 announcements across 17 Alaskan airports, more than for California (61), since
small remote airports re-post hard-to-fill jobs. Weighting by `total_openings` would not fix it:
Alaska has 63 stated openings, California 85, and about half of the postings say Many or Few. This
is the disclosed limit "postings show where DHS hires, not where staff sit", and it shows on a map.
The agent should quote `imputation_quality()` and the imputed share whenever it answers by
location for TSA or CBP.

## By step

| Step | Result |
|---|---|
| 1 Terraform | Plan: `synthetic` created, `agent_semantic` updated in place, `agent_silver` destroyed, nothing replaced. Applied. Grants query as the service principal: `catalog USE_CATALOG`, `semantic EXECUTE`, `semantic SELECT`, `semantic USE_SCHEMA`. Four rows, none on `bronze`, `silver`, or `synthetic`. |
| 2 Imputation | The pools reproduce the spec's coverage exactly. Of 171,627 redacted August rows, 331 have no location pool and 8,815 no pay pool. `posting_locations` has 27,310 rows and none lacks an abbreviation. `posting_pay` has 16,913 rows. `row_number() OVER (PARTITION BY row_hash ORDER BY row_hash)` is accepted. The employment draw takes 14 s on the 2X-Small warehouse (the spec estimated under ten minutes). |
| 3 Staffing plan | 1,680 rows (210 cells × 8 quarters). Six stress rows. FY2027 Q1 `target_onboard` sums to 216,516. |
| 4 Semantic layer | 8 views and 8 functions created. `semantic.headcount_for` and `silver.smoke` dropped. |
| 5 Job | Notebook at `/Workspace/Users/<user>/workforce/03_semantic`. Job `workforce-03-semantic`, id `635037904181578` (in `.env` as `DATABRICKS_SEMANTIC_JOB_ID`). Run `359251154870707`: `SUCCESS`, 71 s. Run `370341863721010`: `SUCCESS`, 66 s. Run `387375520215496`, after the STRING-parameter change: `SUCCESS`, 67 s. |
| 6 Genie | Space `DHS workforce` created from `genie/dhs-workforce.json`. `get-space` shows 8 tables, 8 `sql_functions`, and 6 instruction lines. `workforce-agent` holds `CAN_RUN`. The done-when question is answered below. |
| 7 Acceptance | All pass. The outputs are below and were read through the SQL Statement API, since a warehouse notebook run's cell results are not returned to the CLI. |

## Acceptance outputs

Check cell 1, the August 2026 counts:

```
employment_rows 2,725,190 | separation_rows 27,799 | accession_rows 25,852
aug_redacted 171,627 | aug_location_imputed 171,296 | aug_pay_imputed 162,812 | imputed_not_redacted 0
```

Geocoding covers August 2026 rows with a usable state, which excludes `REDACTED`, `INVALID`, and
foreign `NO DATA REPORTED`:

```
location_imputed | rows    | city_share | no_point
true             | 171,296 | 0.924      | 0
false            |  53,850 | 0.934      | 0
silver.places 32,126 rows; silver.state_centroids 55 rows
```

The exact-name match rate was 87% before normalization. With normalization it is 92% for published
rows and 93% for posting locations. The largest remaining misses are Glynco (FLETC, 538 rows),
Annapolis Junction, Flushing, Honolulu (`Urban Honolulu CDP`), and Williston VT. They fall back to
the state centroid.

Masking test (`imputation_quality()`), recorded and not judged:

```
component | rows_tested | rows_imputed | state_match_share | state_overlap
HSCB FEMA | 18,743      | 17,987       | 0.1174            | 0.6649
HSCA CISA |  2,161      |  1,970       | 0.2817            | 0.7695
```

The function checks:

```
separation_rate('2026-08-01','HSBC','1802'): headcount_start 51,605, headcount_end 46,913,
  separations_ttm 5,922, excl_drp 5,913, quits 3,731, retirements 1,114,
  rate 0.1202, rate_excl_drp 0.1200, files_used 12
plan_variance('FY2026Q1','HSBD','1895'): planned 594, actual 475, variance -119,
  variance_pct -0.2003, is_synthetic true, cells 1, files_used 7
separation_rate('2026-08-01', NULL, NULL): rate 0.1203, rate_excl_drp 0.0989 (DHS)
open_postings('2026-08-01', NULL, NULL): 551 rows (spec: 551 open that day)
attrition_ranking('2026-08-01', 100, 5): CISA 0301 first at 0.5354 (0.3212 excl DRP)
```

The determinism hash covers headcount and the integer sum of pay by component, series, and state
for August 2026. It was `29871f161f9c…` for the ad-hoc build and all three job runs.

## MCP, as the service principal

```
<workspace>/api/2.0/mcp/functions/workforce/semantic -> attrition_ranking, headcount,
  imputation_quality, length_of_service_profile, open_postings, plan_variance,
  posting_coverage, separation_rate   (prefixed workforce__semantic__)
call separation_rate {"as_of_month": "2026-08-01", "component": "HSBC", "series": "1802"} ->
  {"columns":[...],"rows":[[51605,46913,5922,5913,3731,1114,0.1202,0.12,12]]}
```

`synthetic.place_key` sits in `synthetic`, so it is not exposed. This resolves the spec's open
question: the server coerces the string `2026-08-01`, and since the parameters are now STRING, no
coercion is needed anyway. The table-valued-function probe from the spec (`semantic.probe_tvf`,
called over both URLs as the service principal, then dropped) is recorded here as required.

## Genie

The question was "How many TSA screeners by state in August 2026?". Genie's response was one query
attachment with a chart, and no text:

```sql
SELECT * FROM `workforce`.`semantic`.`headcount`(as_of_month => '2026-08-01', component => 'HSBC', series => '1802')
```

The table it returns has 51 states. Each row carries `headcount_location_imputed`, which equals
`headcount` for TSA. The imputation therefore appears as a column, not in prose. The first question
failed until the DATE parameters were changed (Summary, item 1). Whether Genie reads view column
comments is still unverified, because it answered through a trusted function.

## OMB figures

The figures come from OMB Historical Tables, Table 16.1 (FY2027 Budget edition), Homeland Security
column, in thousands of FTE: 219 for FY2025, 227 for the FY2026 estimate, and 224 for the FY2027
estimate. Source: <https://www.whitehouse.gov/omb/information-resources/budget/historical-tables/>.
They are stored in every `generation_rule` of `semantic.staffing_plan`.

## Cost

This is open, just as it was for spec 02. There were three job runs of about 70 s and roughly 60
ad-hoc statements on the 2X-Small warehouse, and two Genie questions. Read the cost from
`system.billing.usage` on 2026-11-01 together with the spec 01 and spec 02 lookups.
