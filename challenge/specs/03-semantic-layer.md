# Spec 03: synthetic schema and semantic layer

**Goal.** The agent gets its only surface: a `semantic` schema of governed views (the object
types) and table-valued SQL functions (the graded metrics) over a new `synthetic` schema that
holds imputed copies of the three OPM tables and the labeled staffing plan. One SQL notebook run
once as a job builds everything; a Genie space sits on the views. Every row with a city gets an
approximate point so the spec 05 dashboard can draw a map. After this spec, every number the eval
will grade has a fixed-SQL function behind it, every imputed or synthetic value is flagged where
the agent reads it, and the spec 02 `silver` tables are untouched.

**Scope, decided 2026-10-31.** Imputation into `synthetic` (`DECISIONS.md`, Imputation). The
defaults built on, stated rather than asked, each measured on the silver tables today:

- **Counting rule.** Separations and accessions are counted by `effective_month` across all
  twelve files, not by the file that reported them. Rows identical on every published column
  that appear in more than one file are the only detectable restatements: 236 of 27,799
  separation rows (0.8%) and 2,331 of 25,852 accession rows (9%; identical new hires in one month
  are common, so most are not restatements). A restatement that changes a column is invisible, so
  this is evidence, not a bound. The recent months are right-censored: of December 2025's 2,643
  separations, 2,003 arrived in later files, and August 2026 has had no later file yet, so
  trailing counts ending in the demo month will grow as files arrive. Every function that counts
  actions says both things in its comment.
- **Imputed columns.** Three of the nineteen redacted location columns are imputed, the three a
  posting supplies: `duty_station_city`, `duty_station_state`, `duty_station_state_abbreviation`.
  Pay is `annualized_adjusted_basic_pay`. The other sixteen stay `REDACTED`. Bargaining unit stays
  as published.
- **The pool is USAJOBS postings.** Location is drawn from posting locations for the same
  component and series; pay from postings for the same component, series, pay plan, and grade.
  Of 171,627 redacted rows in the August 2026 snapshot, 331 (0.2%) have no US posting location in
  their component and series, and 8,815 (5.1%) have no posting at their pay plan and grade; those
  keep `REDACTED` or NULL and the matching flag stays false.
- **Draws are independent per snapshot.** OPM rows carry no id, so the same employee is not
  linked across months. Counts by location are distribution-level; nothing follows an individual.
- **Draws are deterministic.** No `rand()`. Each row's draw is a hash of its published columns
  plus a position among identical rows (45,106 of 225,574 August rows have an identical twin;
  the largest group is 44), so a rerun produces the same tables.
- **The masking test is informational** (Ryan, 2026-10-31: "more art than science"). FEMA and
  CISA are masked and imputed with the same method and the state-distribution overlap is stored and
  disclosed by the agent, but no result changes the design: imputed values stay whatever the
  number. The earlier 0.5 pass bar and its "not published" fallback are withdrawn.
- **Approximate point geometries** (Ryan, 2026-10-31, for a map on the spec 05 dashboard). Every
  OPM row with a city and state, published or imputed, gets `latitude`, `longitude`, and
  `geo_precision` from the Census Bureau's 2025 Gazetteer places file: one interior point per
  incorporated place or census-designated place, 32,350 places, no key, 3.3 MB. On an exact name
  match the gazetteer places 89% of posting-locations and 87% of published August 2026 rows;
  misses are consolidated cities (Indianapolis, Nashville, Honolulu), spelling variants (Lee's
  Summit, Saint Louis), Glynco (a training center, not a place), and Puerto Rico, which OPM
  reports as state `NO DATA REPORTED`. Normalization recovers some; the rest fall back to the
  state's centroid with `geo_precision = 'state'`. Everyone in a city sits on one point; that is
  the resolution a national map needs and no more.
- **Staffing plan.** Component x series x fiscal quarter, FY2026 and FY2027, for cells with at
  least 50 August 2026 employees. Scaled to OMB Historical Table 16.1 (FY2027 edition): DHS
  FTE 227,000 (FY2026 estimate) and 224,000 (FY2027 estimate), against 225,574 August records.
- **Genie** is created on the views, which needs `SELECT` on `semantic` for the service
  principal; the dead `USE_SCHEMA` on `silver` goes, so four grants remain, all on the catalog and
  `semantic` (`DECISIONS.md`, Terraform, amended).
- **Open postings** on a date are those whose `open_date <= date AND close_date >= date`.
  Spec 02's rule used `opening_status`, which is the status on pull day only: for 2026-08-01 it
  returns 724 postings against 551 actually open that day, missing 503 that have since closed.
  Status adds information only on the pull day (`DECISIONS.md`, Data, amended).
- **Question families before functions.** The build-week rule says questions first. The eight
  families in step 5 are the questions; spec 05 instantiates 20 to 30 of them with parameters.
  Object types no family touches are dropped: Agency (one agency, a constant) and DutyStation
  (imputed city and state are columns, not an entity with stable codes).

**Out of scope.** Any AgentCore resource and the agent's instructions (spec 04); the eval set,
harness, and dashboard (spec 05); imputing county, CBSA, locality pay area, or bargaining unit;
linking people across snapshots; a Lakeflow or Asset Bundle job (nothing recurs yet).

**Implements.** Domain model (2026-10-30, corrected), Synthetic data (2026-10-30), Imputation
(2026-10-31), and Counting (2026-10-31) in `DECISIONS.md`. Redaction facts in
[OPM redaction and imputation](../../wiki/analyses/opm-redaction-and-imputation.md); handed-over
facts in [spec 02 results](02-results.md).

**Identities.** Ryan's user runs Terraform and the notebook and owns every object. Views and
functions read `synthetic` and `silver` with the owner's rights (spec 01 step 9 proved this for
functions), so the service principal holds nothing on `synthetic`, `silver`, or `bronze`: the
spec 01 `USE_SCHEMA` on `silver`, which granted nothing readable, is dropped here. It gains
`SELECT` on `semantic` for Genie and `CAN RUN` on the space.

**Rule.** As spec 01: no workspace URL, user name, warehouse id, or space id in a tracked file.
Redact pasted output in `03-results.md`.

**Budget.** Under $2. The notebook hashes 2.7 million employment rows and joins them twice
against pools of under 30,000 rows; the rest is small. Genie questions in the UI are billed to
the warehouse. Nothing runs unattended.

**Files.** `challenge/infra/main.tf` (schema and grant), `challenge/notebooks/03_semantic.sql`
(the build, Databricks SQL notebook source format, written after this spec is read),
`challenge/scripts/pull_sources.py` (new `gazetteer` step), `challenge/scripts/mcp_smoke.py`
(retargeted at a real function), `challenge/example.env`.

## Step 1: Terraform the schema and the Genie grant; land the gazetteer

- **Gazetteer, already done 2026-10-31 while writing this spec.** `python scripts/pull_sources.py
  gazetteer` lands `data/census/2025_Gaz_place_national.txt`; `databricks fs cp -r data/census
  dbfs:/Volumes/workforce/bronze/landing/census --overwrite -p workforce` put it in the volume. The
  local file count is now 66, not spec 02's 65.
- **Do.** In `main.tf`, add `synthetic` to `local.schemas`, add `SELECT` to `agent_semantic`, and
  remove the `agent_silver` grant.

```bash
cd challenge/infra && terraform plan && terraform apply
```

- **Done when.** Plan shows one schema created, one grant updated in place, one grant destroyed,
  nothing replaced. The spec 01 step 4 grants query returns four rows, all on the catalog and
  `semantic`: `USE_CATALOG`, `USE_SCHEMA`, `EXECUTE`, `SELECT`. Nothing on `silver` any more.

## Step 2: the imputation, in the notebook

The pools are two tables in `synthetic`, kept for provenance and reused by the masking test.

**Location pool** `synthetic.posting_locations`: one row per posting x location, from
`silver.job_postings` exploded on `occupational_series_codes` and `locations`, with
`agency_subelement_code` not null (drops the 43 department-level postings), country
`United States`, and a non-empty state (drops the 1,039 "Location Negotiable After Selection" rows
and the foreign ones out of the remaining 28,191). Columns:
`control_number`, `agency_subelement_code`, `series`, `city` and `state` upper-cased to match
OPM, `state_abbreviation` from the distinct (state, abbreviation) pairs on unredacted
`silver.employment` rows, and within each (component, series):
`idx = row_number() OVER (PARTITION BY component, series ORDER BY control_number, city, state)`
and `n = count(*) OVER (PARTITION BY component, series)`. The order must be a total order: 111
postings list the same city name in two states (Charleston, Albany), so `city` alone leaves ties
and a rerun could swap states. The abbreviation lookup is the OPM pairs plus a four-row literal
for the territories OPM never names (`PUERTO RICO` PR, `GUAM` GU, `VIRGIN ISLANDS` VI,
`NORTHERN MARIANA ISLANDS` MP).

**Geocoding** `bronze.census_gazetteer_places` (the pipe-delimited file as received, every column
STRING, via `read_files` with `format => 'csv', sep => '|', header => true`) and `silver.places`:
one row per (`name`, `usps`) with `latitude` and `longitude` from `INTPTLAT` and `INTPTLONG`, where
`name` is `NAME` upper-cased with the legal suffix removed (`city`, `town`, `village`, `CDP`,
`borough`, `municipality`, `comunidad`, `zona urbana`, the `... government (balance)` forms and
`city and borough`), apostrophes and periods dropped, and a leading `ST ` expanded to `SAINT `.
First row wins on a duplicate name. `silver.state_centroids`: mean latitude and longitude of the
places in each `usps`, the fallback point. Both tables are owned by this spec, not spec 02, and
the view comments say the points are approximate.

The same normalization is applied to `duty_station_city` before the lookup. OPM rows with state
`NO DATA REPORTED` and country `US` are tried against `PR` (2,137 published August rows, nearly
all Guaynabo, San Juan, Caguas, and Ponce). Result columns on every synthetic OPM row:
`latitude`, `longitude`, `geo_precision` (`city` on a place match, `state` on the centroid
fallback, NULL when there is no usable state, which includes rows still `REDACTED`).

**Pay pool** `synthetic.posting_pay`: one row per posting x grade, where grade comes from
`explode(sequence(least(a, b), greatest(a, b)))` over the two grades cast to INT when both are
numeric and the minimum grade alone otherwise (94 postings span letter ranges such as `G` to `I`;
only the minimum is used, which the exact counts below depend on), `lpad`ded to two characters
because OPM writes `09` and USAJOBS writes `9` (TSA's `SV` bands are letters on both sides, `ES`
is `00` on both). Keep postings with `minimum_salary >= 20000` (1,025 postings carry placeholder
minimums such as 1.0). Columns: `control_number`, `agency_subelement_code`, `series`,
`pay_plan_code`, `grade`, `minimum_salary`, `maximum_salary`, `idx` and `n` over (component,
series, pay plan, grade) with `idx` ordered by `control_number`.

Each pool also has a counts twin, `n` per key (`synthetic.posting_location_counts` on component
and series; `synthetic.posting_pay_counts` on component, series, pay plan, grade), so the pick
is computed on the employee side and the pool join is a plain equi-join on the key plus `idx`.
Without that, `idx = pmod(hash, pool.n) + 1` is a filter after a (component, series) join, and
TSA 1802 alone is 46,913 x 1,157 rows per snapshot.

**The draw**, applied to each of `silver.employment`, `silver.separations`, `silver.accessions`
to produce `synthetic.employment`, `synthetic.separations`, `synthetic.accessions`:

```sql
WITH r AS (
  SELECT *, xxhash64(to_json(struct(*))) AS row_hash FROM silver.employment),
d AS (
  SELECT *, row_number() OVER (PARTITION BY row_hash ORDER BY row_hash) AS dup_idx FROM r),
k AS (  -- the pick, computed before touching the pools
  SELECT d.*,
    pmod(xxhash64(d.row_hash, d.dup_idx, 'location'), lc.n) + 1 AS loc_pick,
    pmod(xxhash64(d.row_hash, d.dup_idx, 'pay'), pc.n) + 1      AS pay_pick,
    pmod(xxhash64(d.row_hash, d.dup_idx, 'u'), 10000) / 10000.0 AS pay_u
  FROM d
  LEFT JOIN synthetic.posting_location_counts lc
    ON d.pay_redacted AND lc.agency_subelement_code = d.agency_subelement_code
   AND lc.series = d.occupational_series_code
  LEFT JOIN synthetic.posting_pay_counts pc
    ON d.pay_redacted AND pc.agency_subelement_code = d.agency_subelement_code
   AND pc.series = d.occupational_series_code AND pc.pay_plan_code = d.pay_plan_code
   AND pc.grade = lpad(d.grade, 2, '0'))
SELECT k.* EXCEPT (row_hash, dup_idx, loc_pick, pay_pick, pay_u, duty_station_city,
                   duty_station_state, duty_station_state_abbreviation, annualized_adjusted_basic_pay),
  coalesce(l.city, k.duty_station_city)                             AS duty_station_city,
  coalesce(l.state, k.duty_station_state)                           AS duty_station_state,
  coalesce(l.state_abbreviation, k.duty_station_state_abbreviation) AS duty_station_state_abbreviation,
  l.control_number IS NOT NULL                                      AS location_imputed,
  l.control_number                                                  AS location_source_control_number,
  coalesce(p.minimum_salary + k.pay_u * (p.maximum_salary - p.minimum_salary),
           k.annualized_adjusted_basic_pay)                         AS annualized_adjusted_basic_pay,
  p.control_number IS NOT NULL                                      AS pay_imputed,
  p.control_number                                                  AS pay_source_control_number
FROM k
LEFT JOIN synthetic.posting_locations l
  ON l.agency_subelement_code = k.agency_subelement_code AND l.series = k.occupational_series_code
 AND l.idx = k.loc_pick
LEFT JOIN synthetic.posting_pay p
  ON p.agency_subelement_code = k.agency_subelement_code AND p.series = k.occupational_series_code
 AND p.pay_plan_code = k.pay_plan_code AND p.grade = lpad(k.grade, 2, '0') AND p.idx = k.pay_pick;
```

The geocoding is a second pass over the result (a `CREATE OR REPLACE TABLE ... AS SELECT` with
two more left joins): `silver.places` on the normalized final city and the final abbreviation,
then `silver.state_centroids` on the abbreviation, with `geo_precision` from whichever matched.
Two passes keep the draw readable and let the geocoding be rerun alone.

- **Why this shape.** `pay_redacted = true` marks exactly the rows whose location is redacted
  (measured 2026-10-31), so one flag drives both picks; a NULL pick (unredacted row, or no pool)
  matches nothing and the published value stays. `pay_redacted` is NULL, not false, on 1,441
  August rows (1,338 FEMA, 8 CISA) whose pay is missing but location published; NULL is not
  redaction, and the masking test, the view comments, and Genie's instructions say so. The row hash makes identical rows identical draws;
  `dup_idx` spreads them, and because identical rows are indistinguishable the result is the same
  multiset on every run even though window order among them is not stable. Pay is uniform within
  the chosen posting's range; a range that spans several grades overstates the spread, which the
  table comment says.
- **Table comments** on all three: "Synthetic copy of silver.<name>. On rows where OPM redacted
  location and pay, duty station city and state and annualized pay are imputed from USAJOBS DHS
  postings for the same component and series (and pay plan and grade for pay); see
  location_imputed, pay_imputed, and the *_source_control_number columns. Postings show where DHS
  is hiring, not where staff sit. Other redacted columns remain REDACTED. latitude and longitude
  are the Census Gazetteer interior point of the duty station city (geo_precision = city) or the
  mean of the state's places (geo_precision = state); approximate, for maps only. silver.<name>
  is the published record."

**Masking test** `synthetic.imputation_quality`: take the August 2026 rows of FEMA (`HSCB`,
18,743 rows, 931 postings) and CISA (`HSCA`, 2,161 rows, 119 postings) with `pay_redacted = false`
(not NULL, which excludes 1,346 rows whose pay is missing but location published), run the same
draw with the redaction condition forced true, and store per component: rows, share of rows whose
imputed state equals the true state, and distribution overlap (sum over states of the smaller of
the true and imputed shares). The number is recorded and disclosed, nothing more (Scope): the
agent quotes it when a location answer rests on imputed rows, and the results file records it.
Expect it to flatter the method, since FEMA and CISA are office-heavy and hire in a few cities
while TSA and CBP are spread over hundreds of airports and ports, and their postings are too.

## Step 3: the staffing plan, in the notebook

`synthetic.staffing_plan`: one row per component, series, and fiscal quarter FY2026 Q1 to
FY2027 Q4 for cells with at least 50 employees in the August 2026 snapshot. Rule, stored in
`generation_rule` on every row:

- `target_onboard` = OMB FTE for the fiscal year (227,000 for FY2026, 224,000 for FY2027, both
  estimates in Table 16.1 of the FY2027 historical tables, Homeland Security column; FTE is not
  headcount, and the plan says so) x the cell's share of August 2026 headcount. Because the FTE
  targets sit within 1% of the 225,574 August records, this is a near-uniform scaling: every
  FY2026 cell grows by its share of 1,426 and no FY2027 cell grows at all. The plan admits this.
- `planned_hires` per quarter = (non-DRP separations effective September 2025 to August 2026 in
  the cell + max(`target_onboard` − August headcount, 0)) / 4, rounded. Non-DRP because the plan
  replaces ordinary attrition; the deferred-resignation wave is a one-time event.
- Two stress cells, TSA 1802 and CBP 1895: for the FY2026 quarters with a full quarter of
  accessions (Q1 to Q3), `planned_hires = round(actual_accessions / 0.8)`, so hiring lands exactly
  20% under plan on the accessions known today (CBP 1895 FY2026 Q1 is 475); `generation_rule`
  names the stress. Their Q4 and FY2027 rows use the base rule. Right-censoring means later files
  will add accessions to these quarters and the variance will drift toward zero.
- Columns: `agency_subelement_code`, `occupational_series_code`, `fiscal_year`, `fiscal_quarter`
  (`FY2026Q1`), `quarter_start`, `planned_hires`, `target_onboard`, `is_synthetic` (always true),
  `generation_rule`. Comment: "Synthetic Annual Staffing Plan for the demo. In deployment this
  table is the agency's ASP submission."

Fiscal quarter of a month is `add_months(month, 3)`: year and quarter of the shifted date.
Accessions by fiscal quarter today: FY2026 Q1 8,664, Q2 4,454, Q3 4,634, Q4 3,920 (July and
August only; September arrives 2026-11-04).

## Step 4: the semantic layer, in the notebook

**Object types**, as views with column comments. Row-level, DHS only, over `synthetic` where it
exists and `silver` otherwise:

| View | Over | Keeps |
|---|---|---|
| `semantic.component` | `silver.agency_subelements` where parent is `HS` and the code appears in employment | code, name |
| `semantic.occupation` | `silver.occupational_series` | code, name, job family |
| `semantic.workforce_snapshot` | `synthetic.employment` | `snapshot_month`, component, series, pay plan, grade, duty station city and state, `latitude`, `longitude`, `geo_precision`, tenure, length of service, age bracket, supervisory status, work schedule, pay, `pay_redacted`, `location_imputed`, `pay_imputed`, `source_file` |
| `semantic.separation` | `synthetic.separations` | the same plus `effective_month`, `reported_month` (from `source_file`), `separation_category`, `drp_indicator` |
| `semantic.accession` | `synthetic.accessions` | the same plus `effective_month`, `reported_month`, `accession_category` |
| `semantic.job_posting` | `silver.job_postings` | as is, plus `series` = first element of `occupational_series_codes` |
| `semantic.staffing_plan` | `synthetic.staffing_plan` | as is |
| `semantic.imputation_quality` | `synthetic.imputation_quality` | as is |

The spec 05 dashboard map reads `semantic.workforce_snapshot` grouped by city, state, latitude,
and longitude, with the imputed share per point; no function is needed for it, since the
dashboard runs as Ryan's user, not as the agent.

**Metric functions**, table-valued SQL, fixed queries. A NULL `component` or `series` means all
of DHS. Every function returns the provenance the observability page requires: the snapshot or
the count of files used, and the imputed share where a location or pay value enters the answer.

| Function | Returns, one row per | Question family |
|---|---|---|
| `headcount(as_of_month, component, series)` | state: `duty_station_state`, `headcount`, `headcount_location_imputed`, `source_file` | 1. How many, and where, does a component or occupation sit; where is it concentrated |
| `separation_rate(as_of_month, component, series)` | the cell: `headcount_start`, `headcount_end`, `separations_ttm`, `separations_ttm_excl_drp`, `quits`, `retirements`, `rate`, `rate_excl_drp`, `files_used` | 2. What is attrition over the trailing twelve months, with and without the deferred-resignation wave |
| `attrition_ranking(as_of_month, min_headcount, top_n)` | component x series: the `separation_rate` columns, ranked by `rate` | 3. Which cells are losing people fastest |
| `length_of_service_profile(as_of_month, component, series)` | bucket (`<1`, `1-3`, `3-5`, `5-10`, `10-20`, `20+`): `headcount`, `share` | 4. How tenure-heavy is a cell; is a retirement cliff forming |
| `open_postings(as_of_date, component, series)` | posting open on the date: control number, title, grades, `total_openings`, `total_openings_raw`, states, open and close dates | 5. What is advertised against a cell right now |
| `posting_coverage(as_of_date, component, series)` | the cell: `separations_ttm`, `open_postings`, `openings_known`, `postings_many_or_few`, `coverage_ratio` | 6. Is advertised hiring aimed at where people are leaving |
| `plan_variance(fiscal_quarter, component, series)` | the cell: `planned_hires`, `actual_accessions`, `variance`, `variance_pct`, `is_synthetic`, `generation_rule` | 7. How did a quarter's hiring land against the plan, and why |
| `imputation_quality()` | component tested: the masking-test columns | 8. How much should I trust a location answer |

Rules the functions share, stated in each comment: trailing twelve months means effective months
`as_of_month − 11` through `as_of_month`; `headcount_start` is the snapshot at `as_of_month − 11`
(the first month inside the window; for August 2026 that is September 2025, the earliest snapshot,
so August 2026 is the only `as_of_month` with a valid start, which spec 05 must respect) and
`headcount_end` the snapshot at `as_of_month`; rate is separations over the mean of the two; the
latest months are right-censored (Scope); open on a date means
`open_date <= date AND close_date >= date`, which for any past date is an upper bound, since
postings filled or cancelled before their close date are invisible (on pull day, dates say 476
open and status says 427), so spec 05 grades `posting_coverage` against an upper bound; a posting matches a series by
`array_contains(occupational_series_codes, series)`, not the view's first element;
`total_openings` is NULL when the posting says Many or Few, counted separately.

**Cleanup.** Drop `semantic.headcount_for` and `silver.smoke` (spec 01 step 5 said this spec
replaces them). `scripts/mcp_smoke.py` now calls `separation_rate` for TSA 1802 as of
2026-08-01 and asserts a row comes back; the schema-level probe is unchanged.

## Step 5: run it as a job

Same pattern as spec 02 step 3: import `notebooks/03_semantic.sql` to
`/Workspace/Users/<user>/workforce/03_semantic`, create job `workforce-03-semantic` on the
warehouse, `run-now --timeout 60m`, record the job id in `.env` as `DATABRICKS_SEMANTIC_JOB_ID`.
Rerunning replaces every object.

## Step 6: Genie space

- **Do.** In the UI: Genie, New, title `DHS workforce`, data: the eight `semantic` views, default
  warehouse. Instructions, six lines: DHS only; count separations and accessions by
  `effective_month`; `drp_indicator = 'Y'` is the 2025 deferred resignation program; where
  `location_imputed` or `pay_imputed` is true the value is synthetic, drawn from USAJOBS postings,
  and must be labeled; `pay_redacted` NULL is missing, not redacted; `staffing_plan` is synthetic.
  Add the eight functions as trusted assets, so Genie's answers to the eight question families
  come back verified and reuse the graded SQL instead of regenerating it. Share with
  `workforce-agent`, `CAN RUN`. Record the space id in `.env` as `DATABRICKS_GENIE_SPACE_ID`.
- **Done when.** "How many TSA screeners by state in August 2026?" answers with a state table and
  mentions imputed locations. The MCP call as the service principal is spec 04's handshake.

## Step 7: acceptance

Check cells at the end of the notebook, read through the SQL Statement API as in spec 02:

- `synthetic.employment` has 2,725,190 rows, `separations` 27,799, `accessions` 25,852 (the silver
  counts). August 2026: 171,627 rows with `pay_redacted`; `location_imputed` true on exactly
  171,296 of them (171,627 − 331) and `pay_imputed` on exactly 162,812 (171,627 − 8,815): every
  redacted row in a cell with a pool gets a match, since the pick is always within `1..n`. No row
  has `location_imputed` or `pay_imputed` true with `pay_redacted` false.
- **Determinism.** Run the job twice. Headcount by component, series, and imputed state for
  August 2026 is identical between runs (compare a hash of the ordered result).
- `imputation_quality`: two rows; state-match share and overlap recorded for FEMA and CISA.
- **Geocoding.** Of August 2026 rows with a non-NULL final state, at least 85% have
  `geo_precision = 'city'`, none have NULL; `silver.places` has about 32,000 rows and
  `silver.state_centroids` 56 or so (states, DC, territories). Record the city-precision share
  separately for published and imputed rows.
- `staffing_plan`: 8 rows per cell, 210 cells (the 1,005 component x series cells minus those
  under 50 employees, which hold 7,542 of the 225,574 records); TSA 1802 and CBP 1895 FY2026 Q1 to
  Q3 rows carry the stress rule; `target_onboard` summed over cells for any one FY2027 quarter is
  about 216,500 (224,000 less the small-cell share).
- `separation_rate('2026-08-01', 'HSBC', '1802')` returns one row with `files_used = 12` and
  `rate_excl_drp < rate`.
- `plan_variance('FY2026Q1', 'HSBD', '1895')` returns `variance_pct` near −20% and
  `is_synthetic = true`.
- `python scripts/mcp_smoke.py` as the service principal lists eight tools at the schema URL and
  the `separation_rate` call returns a row. Until the notebook has run, the script fails on a
  missing function; that is expected.
- The grants query returns four rows, all on the catalog and `semantic`; none on `bronze`,
  `silver`, or `synthetic`.
- `03-results.md` records the OMB figures with the download URL and the table-valued-function
  probe, which so far exist only in this spec.

## Results file

`challenge/specs/03-results.md`, redacted: run ids and durations for both runs, the acceptance
numbers above, the masking-test numbers, the geocoding shares, the pay-imputed count, Genie's
answer to the done-when question, the MCP tool list, and anything that did not match this spec.

## Teardown

Everything goes with the catalog in `terraform destroy`. The Genie space is deleted in the UI.
Locally, `rm -rf challenge/data` as in spec 02 (the census file is under it).

## Settled before writing (2026-10-31, on the silver tables)

- Grade formats: OPM `grade` is `05`, `07`, `09` for GS and GL, letters `D` to `G` for TSA `SV`,
  `00` for `ES`; USAJOBS `minimum_grade` and `maximum_grade` are `5`, `7`, `9`, the same letters,
  `00`. Postings for 1811 and 1895 span ranges (`9` to `12`, `5` to `7`).
- Posting locations: `positionLocationCity`, `positionLocationState`, `positionLocationCountry`;
  state is a title-case full name (`Texas`), OPM's is upper case (`TEXAS`) with a separate
  abbreviation column. Washington DC leads with 2,454 posting-locations.
- Pool coverage after the US-and-state filter: TSA 1802 has 1,155 postings and 1,157
  posting-locations (one airport each); CBP 1895 344 and 831; CBP 1896 824 and 1,357; ICE 1811
  only 17 postings but 772 locations.
- Restatement and duplicates: the numbers in Scope.
- OMB Table 16.1, FY2027 edition: Homeland Security 219 (FY2025), 227 (FY2026 estimate),
  224 (FY2027 estimate), thousands of FTE. The DHS column is a department line; no crosswalk.
- Gazetteer: `USPS|GEOID|GEOIDFQ|ANSICODE|NAME|LSAD|FUNCSTAT|ALAND|AWATER|ALAND_SQMI|AWATER_SQMI|INTPTLAT|INTPTLONG`,
  32,350 rows, 32,126 distinct (name, state) after suffix stripping. Exact-name match before the
  apostrophe, period, and Saint rules: 24,276 of 27,152 US posting-locations (89.4%), 45,857 of
  52,449 published August rows (87.4%). Largest misses: Indianapolis 326 and 'NEW YORK - NEW YORK'
  601 (consolidated or hyphenated forms), Glynco 313 and 538, Guaynabo 1,009 (state
  `NO DATA REPORTED`), Lee's Summit 117 and 410, Honolulu 146 and 170.
- OPM state values include `NO DATA REPORTED` (`NDR`, 2,137 US rows, Puerto Rico) and `INVALID`
  (`*`, 39 rows); neither is a state, both fall to NULL geometry unless the PR heuristic matches.
- **Table-valued functions work over the MCP functions server.** A throwaway
  `semantic.probe_tvf(component)` returning a one-row table was called as the service principal
  through both the per-function and the schema URL; the result came back as
  `{"columns":["component","n"],"rows":[["HSBC",1]]}`. Dropped afterwards. Spec 01 had proved
  only a scalar function.

## Not verified before writing

- `row_number() OVER (PARTITION BY row_hash ORDER BY row_hash)`: ordering by the partition key
  should be accepted as a constant order. If it is refused, order by a published column.
- Warehouse time for the hash pass and the four equi-joins over 2.7 million rows; the estimate
  is under ten minutes.
- Whether Genie reads view column comments as its semantic context (the docs say it does) and
  whether `CAN RUN` can be granted to a service principal from the share dialog.
- Whether the MCP functions server coerces a DATE parameter passed as the string `2026-08-01`.
  The smoke script assumes it does.
- `read_files` on a pipe-delimited `.txt` with `sep => '|'` and a UTF-8 BOM in the header (the
  file starts with one); if `USPS` comes back as `﻿USPS`, strip it or select by position.
- How much the name normalization adds over the exact-name 87 to 89%; the 85% city-precision
  bar assumes a few points.
