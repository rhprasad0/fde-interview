# Spec 02: one-time load of OPM and USAJOBS into bronze and silver

**Goal.** Twelve months of OPM Federal Workforce Data and the DHS slice of USAJOBS land once in
the `landing` volume from a laptop, and a SQL notebook run once as a job turns them into bronze
tables (whole government, as received) and silver tables (DHS only, typed). After this spec the
semantic layer has real rows to build on and nothing refreshes.

**Scope, decided 2026-10-31.** One-time load, no refresh job (Ryan: the egress blocker is
documented, that is enough). The defaults built on, stated rather than asked:

- OPM Employment, Separations, and Accessions for September 2025 through August 2026, the latest
  published month. September 2026 is due 2026-11-04, after the freeze; the demo runs on August data.
- Bronze keeps every file whole-government with every column a STRING; silver filters to
  `agency_code = 'HS'` and casts.
- Demand is the USAJOBS Historic JOA (no key) for DHS announcements opened 2025-09-01 to
  2026-10-31. The Search API is not loaded: Historic JOA carries each announcement's status and
  close date, so "open on a date" is status `Accepting applications` with a close date on or
  after it. Status alone lags: of 724 rows with that status on pull day, 297 had already closed,
  so 427 were open (`DECISIONS.md`, Data, amended).
- Two USAJOBS code lists (agency subelements, occupational series) as governed dimension tables.

**Out of scope.** The semantic layer, Genie space, and column comments (spec 03); any scheduled
or Asset-Bundle job (nothing recurs yet; the spec 05 job starts at silver); data-quality checks
beyond row counts; the OMB Table 16.1 enrichment.

**Implements.** Data (2026-10-30, amended 2026-10-31) and Ingest (2026-10-31, amended) in
`DECISIONS.md`. Source facts in [candidate data sources](../../wiki/analyses/candidate-data-sources.md).

**Identities.** Ryan's user pulls, uploads, imports, and runs the notebook, and owns every table.
The service principal is untouched: it holds no privilege on `bronze` or `silver`, and the step 4
grants query from spec 01 must still return four rows.

**Rule.** As spec 01: no workspace URL, user name, or warehouse id in a tracked file. Redact
pasted output in `02-results.md` to `<workspace>` and `<user>`.

**Budget.** Under $2. The notebook keeps the 2X-Small warehouse busy for an estimated 10 to 20
minutes (about 24 million employment rows copied into Delta, the rest is small). Storage is about
0.7 GB in the volume plus the Delta copies. Nothing runs unattended.

**Files.** `challenge/scripts/pull_sources.py` (laptop pull), `challenge/notebooks/02_load.sql`
(the load, Databricks SQL notebook source format), `challenge/data/` (gitignored staging).

## Step 1: pull the source files to the laptop

- **Why a laptop.** Serverless compute refuses DNS for both federal hosts (spec 01, step 11).
- **Do.** From `challenge/` with the spec 01 venv (`httpx` is already installed):

```bash
cd challenge && source .venv/bin/activate
python scripts/pull_sources.py            # or a subset: python scripts/pull_sources.py employment
```

- The script reads each OPM dataset's list endpoint and takes the current version per month;
  versions differ by dataset and month (June 2026 is v3 for employment, v4 for separations), so
  it never constructs one. Downloads are
  `/api/v1/files/{dataset}/{yyyy}/{mm}/{version}/download`. Employment is about 57 MB a month;
  the other two are under 1 MB. Historic JOA pages 500 rows through a continuation token and the
  script asserts the row total matches the API's `totalCount`. Everything lands under
  `challenge/data/` with the layout the notebook expects.
- **Already done 2026-10-31 while writing this spec:** `separations`, `accessions`, `joa`, and
  `codelists` (two minutes; 36 small files, 13,136 announcements). Only `employment` remains
  (12 files, about 690 MB).
- **Done when.** `find data -type f | wc -l` prints 65: 36 Parquet files under `data/opm/`, 27
  JSON pages under `data/usajobs/historicjoa/`, 2 code lists under `data/usajobs/codelist/`.

## Step 2: upload to the landing volume

```bash
databricks fs cp -r data dbfs:/Volumes/workforce/bronze/landing --overwrite -p workforce
databricks fs ls dbfs:/Volumes/workforce/bronze/landing/opm/employment -p workforce
```

- `fs cp -r` maps the local tree onto the volume one for one, into a new or an existing
  directory alike (verified 2026-10-31 with the code lists, which are already in
  `landing/usajobs/codelist/`, including the `--overwrite` rerun). About 0.7 GB; a few minutes.
- **Done when.** The volume shows `opm/{employment,separations,accessions}` with 12 files each,
  `usajobs/historicjoa` with 27, `usajobs/codelist` with 2.

## Step 3: import the notebook and run it once as a job on the warehouse

- **Why a named job, not the SQL editor or a one-off submit.** A created job appears in the Jobs
  UI with its run history, so the deep dive can open the run that built every table. A
  `jobs submit` one-off is not saved as a job and shows up only in the Runs tab by id. The
  notebook task runs on the existing 2X-Small warehouse, so no new compute. Rerunning the job
  replaces every table.
- **Do.** `<user>` is the `userName` from `databricks current-user me -p workforce`;
  `<warehouse-id>` is in `.env`. The CLI waits for the run and gives up (the run continues) after
  20 minutes by default, so pass a longer timeout.

```bash
databricks workspace mkdirs /Workspace/Users/<user>/workforce -p workforce
databricks workspace import /Workspace/Users/<user>/workforce/02_load \
  --file notebooks/02_load.sql --language SQL --format SOURCE --overwrite -p workforce
databricks jobs create --json '{
  "name": "workforce-02-load",
  "tasks": [{"task_key": "load",
             "notebook_task": {"notebook_path": "/Workspace/Users/<user>/workforce/02_load",
                               "warehouse_id": "<warehouse-id>"}}]}' -p workforce
databricks jobs run-now <job-id> --timeout 60m -p workforce
```

- **Done when.** The run ends in `SUCCESS` (otherwise `databricks jobs get-run <run-id> -p
  workforce`), and the notebook's check cells, read in the run output, show the expected numbers
  (step 4). Record the job id in `.env` as `DATABRICKS_LOAD_JOB_ID`.

## Step 4: acceptance

From the run output or the SQL editor, the notebook's check cells must show:

- Ten tables. The three bronze OPM tables each have 12 distinct `source_file` values and zero
  non-null `_rescued_data` (no column drift across files); silver `employment` has 12 snapshot
  months, `separations` and `accessions` 12 source files each.
- `employment_202608_1.parquet` contributed 2,024,832 rows (verified 2026-10-30).
  `separations_202509_5.parquet` has 120,540 rows against 12,000 to 37,000 for every other
  month (Parquet footers, 2026-10-31; the deferred-resignation wave is the likely cause and
  `drp_indicator` will say). Any trailing-twelve-month rate in spec 03 is dominated by that file.
- TSA (`HSBC`) rows from `separations_202608_1.parquet`: 512 (counted the same way 2026-10-30).
- The last cell shows, per separations file, the earliest and latest effective month and how
  many rows took effect in the file's own month. The footers already show each file reaching
  about two years back, so expect few rows in the last column. Spec 03 must decide whether to
  count by month reported or by effective month, and whether later files restate earlier actions
  (OPM rows carry no action id, so restated actions cannot be deduplicated).
- `silver.job_postings`: 13,136 rows and 13,136 distinct control numbers; 724 with status
  `Accepting applications`, 427 of those with a close date on or after 2026-10-31; 43
  department-level rows (`agency_level = 1`) with a NULL subelement code (verified from the
  pulled files 2026-10-31).
- `silver.agency_subelements` 1,072 rows; `silver.occupational_series` 822.
- The spec 01 step 4 grants query still returns four rows, none on `bronze` or `silver` tables.

If a bronze count is short, a month is missing from the volume (step 2). If a silver OPM table is
empty, check the DHS code: `SELECT agency_code, agency FROM bronze.opm_separations WHERE agency
LIKE 'DEPARTMENT OF HOMELAND%' LIMIT 1`.

## Results file

`challenge/specs/02-results.md`, redacted per the Rule: file counts and total size pulled, upload
time, the job run id and duration, the two check-cell outputs, the warehouse cost from
`system.billing.usage` the next morning, and anything that did not match this spec.

## Teardown

The tables go with the catalog in `terraform destroy` (spec 01). Locally, `rm -rf challenge/data`.

## Settled by the adversarial review (2026-10-31)

- Column sets are identical across the 12 separations files (69 columns) and the 12 accessions
  files (68), from the Parquet footers. Employment is unpulled; `_rescued_data` in bronze is the
  guard and the first check cell counts it.
- Historic JOA pages infer one stable schema: 40 keys on every row, control number always an
  integer, grades always strings, `totalOpenings` always a string or null (`Many`, `Few` and case
  variants, 1,491 rows; 1,548 null), the three nested arrays always arrays of uniform objects,
  `hiringpaths` null on one row.
- Pay carries the literal `REDACTED`, and ANSI mode would fail a plain `CAST`; silver uses
  `try_cast` and keeps `pay_redacted`.
- `read_files` exposes `_metadata.file_name` with the extension; `notebook_task.warehouse_id`
  works on a serverless or pro warehouse; Markdown cells are fine in a warehouse-backed notebook
  task; the CLI waits for the run with a 20-minute default timeout.

## Not verified before writing

- `to_date(x, 'yyyyMM')`: Spark defaults the day to 1, and the values are all six digits with
  no nulls. If ANSI mode rejects the pattern, use `to_date(concat(x, '01'), 'yyyyMMdd')`.
- Whether `USE CATALOG` persists across cells of a warehouse-backed job run. The docs say
  warehouse notebooks keep session state; if a cell fails on a missing table, qualify the names.
- Warehouse time for the employment copy; the estimate is 10 to 20 minutes.
