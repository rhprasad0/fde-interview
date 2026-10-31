# Spec 02 results

Executed 2026-10-31. Redacted per the Rule: host is `<workspace>`, user is `<user>`, and the
warehouse id stays in `.env`. Spec: [02-one-time-load.md](02-one-time-load.md).

## Summary

Ten tables loaded in one job run, and every pass/fail number in step 4 matched. The run took
2 minutes 17 seconds, against the spec's 10 to 20 minute estimate. The service principal's
grants are unchanged. One expectation was wrong: the spec guessed that few separations take effect in
the month of the file that reports them, but 75% of DHS rows do (below). The warehouse cost is
**open**: billing rows arrive within about 12 hours. Record it on 2026-11-01 together with spec 01,
step 10.

## By step

| Step | Result |
|---|---|
| 1 Pull | `employment` pulled in this session: 12 files, 57 to 71 MB each. `find data -type f \| wc -l` = 65 (36 Parquet, 27 JOA pages, 2 code lists), 761 MB in total. Versions taken from the list endpoint: employment 202509 to 202512 are v4, 202601 and 202602 v3, 202603 to 202605 v2, 202606 v3, 202607 v2, 202608 v1. |
| 2 Upload | `fs cp -r data ... --overwrite`: 68 seconds. Volume counts: employment 12, separations 12, accessions 12, historicjoa 27, codelist 2. |
| 3 Job | Notebook imported to `/Workspace/Users/<user>/workforce/02_load`. Job `workforce-02-load`, id `397893131903451` (in `.env` as `DATABRICKS_LOAD_JOB_ID`). Run `1076376052023462` (task run `647377036959323`), `SUCCESS`, execution 137 s, 2 min 27 s wall time from the CLI. |
| 4 Acceptance | All pass (outputs below). The check cells were rerun word for word through the SQL Statement API on the same warehouse, because a warehouse notebook run's cell results are not returned to the CLI. |

## Check cell 1: tables

```
t                           | n          | files  | rescued
bronze.opm_employment       | 24,660,738 | 12     | 0
bronze.opm_separations      |    335,446 | 12     | 0
bronze.opm_accessions       |    167,852 | 12     | 0
bronze.usajobs_historicjoa  |     13,136 | 27     | 0
silver.employment           |  2,725,190 | 12     | -
silver.separations          |     27,799 | 12     | -
silver.accessions           |     25,852 | 12     | -
silver.job_postings         |     13,136 | 13,136 | -
silver.agency_subelements   |      1,072 | 1,072  | -
silver.occupational_series  |        822 | 822    | -
```

`files` is distinct `source_file` for the bronze tables and for silver separations and accessions,
distinct `snapshot_month` for silver employment, and distinct keys for the rest. `_rescued_data`
is null on every bronze row, so no column drifted across the 12 employment files (their footers
had not been checked before this run).

## Check cell 2: anchors

| Check | Expected | Got |
|---|---|---|
| `employment_202608_1.parquet` rows | 2,024,832 | 2,024,832 |
| `separations_202509_5.parquet` rows | 120,540 | 120,540 |
| TSA (`HSBC`) rows, `separations_202608_1` | 512 | 512 |
| Postings with status Accepting applications | 724 | 724 |
| ... and close date on or after 2026-10-31 | 427 | 427 |
| Department-level postings (`agency_level = 1`) | 43 | 43 |

## Check cell 3: effective month per DHS separations file (fact for spec 03)

```
source_file                  | rows  | earliest   | latest     | rows_effective_in_file_month
separations_202509_5.parquet | 5,000 | 2023-09-01 | 2025-09-01 | 4,903
separations_202510_5.parquet | 2,669 | 2023-10-01 | 2025-10-01 | 2,660
separations_202511_5.parquet | 2,334 | 2023-11-01 | 2025-11-01 | 1,078
separations_202512_4.parquet |   827 | 2023-12-01 | 2025-12-01 |   640
separations_202601_3.parquet | 3,591 | 2024-01-01 | 2026-01-01 | 1,376
separations_202602_3.parquet | 1,521 | 2024-02-01 | 2026-02-01 |   898
separations_202603_2.parquet | 2,201 | 2024-03-01 | 2026-03-01 | 1,264
separations_202604_2.parquet | 2,000 | 2024-09-01 | 2026-04-01 | 1,431
separations_202605_2.parquet | 2,375 | 2024-05-01 | 2026-05-01 | 2,115
separations_202606_4.parquet | 1,634 | 2024-06-01 | 2026-06-01 | 1,369
separations_202607_2.parquet | 2,184 | 2024-07-01 | 2026-07-01 | 1,768
separations_202608_1.parquet | 1,463 | 2025-07-01 | 2026-08-01 | 1,375
```

**Conflicts with the spec**, which expected "few rows in the last column". Across the 12 files,
20,877 of 27,799 DHS rows (75%) took effect in the file's own month. The two-year reach is a
tail, but not a thin one in every month: November 2025 (46% in month) and January 2026 (38%)
carry many late-reported actions. The latest effective month always equals the file month, so
no file reports a future-dated action.

## Grants (spec 01 step 4 query, rerun)

```
catalog | workforce | USE_CATALOG
schema  | silver    | USE_SCHEMA
schema  | semantic  | EXECUTE
schema  | semantic  | USE_SCHEMA
```

The same four rows as [spec 01](01-results.md), in a different order. `information_schema.table_privileges`
has 0 rows for the service principal, so it holds no grant on any bronze or silver table.

## Facts handed to spec 03

- **Month reported or effective month.** Each monthly Separations and Accessions file holds
  actions effective up to about two years before the file month. Rows carry no action id, so an
  action restated in a later file cannot be deduplicated. Spec 03 must count either by
  `source_file` (month reported) or only rows whose `effective_month` equals the file month, and
  say which. Counting only rows effective in the file month keeps 75% of DHS rows overall and
  under half in November 2025 and January 2026 (cell 3).
- **The September 2025 separations file dominates.** Government-wide it has 120,540 rows, of
  which 96,177 carry `drp_indicator = 'Y'` (the deferred resignation program). For DHS it has 5,000 rows,
  2,363 of them DRP, against 827 to 3,591 in every other month. The DHS rows in the August 2026 file have no DRP flag. Any
  trailing-twelve-month separation rate is dominated by that file; expose `drp_indicator` or
  show the rate with and without it.
- **Open postings** on a date: `opening_status = 'Accepting applications' AND close_date >= date`.
  Status alone overstates: 724 against 427 on 2026-10-31.
- **Pay.** `pay_redacted` marks rows where OPM published `REDACTED`; `annualized_adjusted_basic_pay`
  is NULL on those rows.
- **Join keys.** `silver.job_postings.agency_subelement_code` joins OPM `agency_subelement_code`
  (TSA is `HSBC` in both). It is NULL on the 43 department-level postings.

## Deviations from the spec

- **Run time.** 137 seconds, not 10 to 20 minutes. Copying 24.7 million employment rows into Delta was fast on 2X-Small.
- **Reading the check cells.** Read through the SQL Statement API instead of the run page; same
  SQL, same warehouse.
- **Cell 3 expectation.** See above.
- **Neither untested fallback was needed.** `to_date(x, 'yyyyMM')` worked under ANSI mode, and
  `USE CATALOG` persisted across the cells of the warehouse-backed job run.
- **`.env` parsing.** `DATABRICKS_WAREHOUSE_ID` carries an inline comment, so `cut -d= -f2-`
  alone passes the comment to the API; strip from `#` before use.

## Open

- Warehouse cost of the run from `system.billing.usage`, due 2026-11-01 (next morning), with
  spec 01 step 10.
