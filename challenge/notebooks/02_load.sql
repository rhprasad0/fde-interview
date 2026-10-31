-- Databricks notebook source
-- MAGIC %md
-- MAGIC # Spec 02: one-time load of the landing volume into bronze and silver
-- MAGIC
-- MAGIC **Bronze** keeps every file as received: whole government, every OPM column a STRING, plus
-- MAGIC `source_file` so each row traces to the published file (for example `employment_202608_1`).
-- MAGIC **Silver** filters to DHS (`agency_code = 'HS'`), casts the numeric and date columns, and
-- MAGIC renames USAJOBS fields to the OPM names they join on. Runs once on the SQL warehouse as a
-- MAGIC one-off job (spec 02, step 3). Rerunning replaces every table.

-- COMMAND ----------

USE CATALOG workforce;

-- COMMAND ----------

-- MAGIC %md ## Bronze: OPM Federal Workforce Data, twelve months ending August 2026

-- COMMAND ----------

CREATE OR REPLACE TABLE bronze.opm_employment
COMMENT 'OPM FWD Employment month-end snapshots, 2025-09 to 2026-08, whole government, as published; every column STRING'
AS SELECT *, _metadata.file_name AS source_file
FROM read_files('/Volumes/workforce/bronze/landing/opm/employment/', format => 'parquet');

-- COMMAND ----------

CREATE OR REPLACE TABLE bronze.opm_separations
COMMENT 'OPM FWD Separations (actions leaving federal service), 2025-09 to 2026-08, whole government, as published; every column STRING'
AS SELECT *, _metadata.file_name AS source_file
FROM read_files('/Volumes/workforce/bronze/landing/opm/separations/', format => 'parquet');

-- COMMAND ----------

CREATE OR REPLACE TABLE bronze.opm_accessions
COMMENT 'OPM FWD Accessions (new hires and transfers in), 2025-09 to 2026-08, whole government, as published; every column STRING'
AS SELECT *, _metadata.file_name AS source_file
FROM read_files('/Volumes/workforce/bronze/landing/opm/accessions/', format => 'parquet');

-- COMMAND ----------

-- MAGIC %md ## Bronze: USAJOBS Historic JOA and code lists

-- COMMAND ----------

CREATE OR REPLACE TABLE bronze.usajobs_historicjoa
COMMENT 'USAJOBS Historic JOA: DHS announcements opened 2025-09-01 to 2026-10-31, as returned by the API; one row per announcement'
AS SELECT *, _metadata.file_name AS source_file
FROM read_files('/Volumes/workforce/bronze/landing/usajobs/historicjoa/', format => 'json');

-- COMMAND ----------

CREATE OR REPLACE TABLE bronze.usajobs_agencysubelements
COMMENT 'USAJOBS code list: agency subelements with parent department, as returned'
AS SELECT * FROM read_files('/Volumes/workforce/bronze/landing/usajobs/codelist/agencysubelements.json', format => 'json');

-- COMMAND ----------

CREATE OR REPLACE TABLE bronze.usajobs_occupationalseries
COMMENT 'USAJOBS code list: occupational series with job family, as returned'
AS SELECT * FROM read_files('/Volumes/workforce/bronze/landing/usajobs/codelist/occupationalseries.json', format => 'json');

-- COMMAND ----------

-- MAGIC %md ## Silver: DHS only, typed
-- MAGIC
-- MAGIC OPM publishes every column as a string; `count` is always 1. Pay is the literal `REDACTED`
-- MAGIC on some rows, so numeric casts use `try_cast` and `pay_redacted` keeps the distinction. The
-- MAGIC `yyyymm` fields become first-of-month dates. Each monthly Separations and Accessions file
-- MAGIC carries actions with effective months reaching about two years back (late-reported actions),
-- MAGIC so `source_file` is the month reported and `effective_month` the month it happened.
-- MAGIC `_rescued_data` stays in bronze as the schema-drift guard and is dropped here.

-- COMMAND ----------

CREATE OR REPLACE TABLE silver.employment
COMMENT 'DHS employee records at each month-end snapshot, 2025-09 to 2026-08; one row per employee record, count = 1. From bronze.opm_employment, DHS filter and casts'
AS SELECT * EXCEPT (`count`, length_of_service_years, annualized_adjusted_basic_pay, _rescued_data),
  CAST(`count` AS INT) AS `count`,
  try_cast(length_of_service_years AS DOUBLE) AS length_of_service_years,
  try_cast(annualized_adjusted_basic_pay AS DOUBLE) AS annualized_adjusted_basic_pay,
  annualized_adjusted_basic_pay = 'REDACTED' AS pay_redacted,
  to_date(snapshot_yyyymm, 'yyyyMM') AS snapshot_month
FROM bronze.opm_employment
WHERE agency_code = 'HS';

-- COMMAND ----------

CREATE OR REPLACE TABLE silver.separations
COMMENT 'DHS separations reported in the monthly files 2025-09 to 2026-08; one row per action, count = 1. effective_month is when the action took effect and can precede the file month by up to two years. From bronze.opm_separations, DHS filter and casts'
AS SELECT * EXCEPT (`count`, length_of_service_years, annualized_adjusted_basic_pay, _rescued_data),
  CAST(`count` AS INT) AS `count`,
  try_cast(length_of_service_years AS DOUBLE) AS length_of_service_years,
  try_cast(annualized_adjusted_basic_pay AS DOUBLE) AS annualized_adjusted_basic_pay,
  annualized_adjusted_basic_pay = 'REDACTED' AS pay_redacted,
  to_date(personnel_action_effective_date_yyyymm, 'yyyyMM') AS effective_month
FROM bronze.opm_separations
WHERE agency_code = 'HS';

-- COMMAND ----------

CREATE OR REPLACE TABLE silver.accessions
COMMENT 'DHS accessions reported in the monthly files 2025-09 to 2026-08; one row per action, count = 1. effective_month is when the action took effect and can precede the file month by up to two years. From bronze.opm_accessions, DHS filter and casts'
AS SELECT * EXCEPT (`count`, length_of_service_years, annualized_adjusted_basic_pay, _rescued_data),
  CAST(`count` AS INT) AS `count`,
  try_cast(length_of_service_years AS DOUBLE) AS length_of_service_years,
  try_cast(annualized_adjusted_basic_pay AS DOUBLE) AS annualized_adjusted_basic_pay,
  annualized_adjusted_basic_pay = 'REDACTED' AS pay_redacted,
  to_date(personnel_action_effective_date_yyyymm, 'yyyyMM') AS effective_month
FROM bronze.opm_accessions
WHERE agency_code = 'HS';

-- COMMAND ----------

CREATE OR REPLACE TABLE silver.job_postings
COMMENT 'USAJOBS announcements for DHS components opened 2025-09-01 to 2026-10-31; one row per announcement. agency_subelement_code joins OPM agency_subelement_code (HSBC is TSA in both) and is NULL for department-level postings (agency_level = 1). Open on a date means opening_status = Accepting applications AND close_date >= that date; status alone lags. total_openings is NULL when the posting says Many or Few; see total_openings_raw'
AS SELECT
  CAST(usajobsControlNumber AS STRING)            AS control_number,
  announcementNumber                              AS announcement_number,
  hiringDepartmentCode                            AS agency_code,
  agencyLevel                                     AS agency_level,
  IF(agencyLevel = 1, NULL, hiringAgencyCode)     AS agency_subelement_code,
  hiringAgencyName                                AS agency_subelement,
  hiringSubelementName                            AS hiring_office,
  positionTitle                                   AS position_title,
  transform(jobcategories, c -> c.series)         AS occupational_series_codes,
  positionlocations                               AS locations,
  CAST(minimumGrade AS STRING)                    AS minimum_grade,
  CAST(maximumGrade AS STRING)                    AS maximum_grade,
  payScale                                        AS pay_plan_code,
  try_cast(minimumSalary AS DOUBLE)               AS minimum_salary,
  try_cast(maximumSalary AS DOUBLE)               AS maximum_salary,
  try_cast(totalOpenings AS INT)                  AS total_openings,
  CAST(totalOpenings AS STRING)                   AS total_openings_raw,
  to_date(positionOpenDate)                       AS open_date,
  to_date(positionCloseDate)                      AS close_date,
  to_date(positionExpireDate)                     AS expire_date,
  positionOpeningStatus                           AS opening_status,
  transform(hiringpaths, h -> h.hiringPath)       AS hiring_paths,
  whoMayApply                                     AS who_may_apply,
  teleworkEligible                                AS telework_eligible,
  securityClearance                               AS security_clearance,
  source_file
FROM bronze.usajobs_historicjoa;

-- COMMAND ----------

CREATE OR REPLACE TABLE silver.agency_subelements
COMMENT 'USAJOBS agency subelement code list; agency_code is the parent department (HS for DHS)'
AS SELECT Code AS agency_subelement_code, Value AS agency_subelement, ParentCode AS agency_code,
  IsDisabled = 'Yes' AS is_disabled
FROM bronze.usajobs_agencysubelements;

-- COMMAND ----------

CREATE OR REPLACE TABLE silver.occupational_series
COMMENT 'USAJOBS occupational series code list with job family'
AS SELECT Code AS occupational_series_code, Value AS occupational_series, JobFamily AS job_family_code,
  IsDisabled = 'Yes' AS is_disabled
FROM bronze.usajobs_occupationalseries;

-- COMMAND ----------

-- MAGIC %md ## Checks
-- MAGIC
-- MAGIC Expected, from the APIs (2026-10-30, 2026-10-31) and the pulled files' Parquet footers:
-- MAGIC 12 source files per OPM table; `employment_202608_1` has 2,024,832 rows; 512 TSA (`HSBC`)
-- MAGIC rows in the August 2026 separations file; `separations_202509_5` has 120,540 rows against
-- MAGIC 12,000 to 37,000 for every other month; `job_postings` has 13,136 rows, all distinct, 724
-- MAGIC with status Accepting applications and 427 of those with a close date on or after
-- MAGIC 2026-10-31; 43 department-level postings with a NULL subelement code; agency subelement
-- MAGIC list 1,072 rows, series list 822; `_rescued_data` null everywhere in bronze.

-- COMMAND ----------

SELECT 'bronze.opm_employment' AS t, count(*) AS n, count(DISTINCT source_file) AS files, count(_rescued_data) AS rescued FROM bronze.opm_employment
UNION ALL SELECT 'bronze.opm_separations', count(*), count(DISTINCT source_file), count(_rescued_data) FROM bronze.opm_separations
UNION ALL SELECT 'bronze.opm_accessions', count(*), count(DISTINCT source_file), count(_rescued_data) FROM bronze.opm_accessions
UNION ALL SELECT 'bronze.usajobs_historicjoa', count(*), count(DISTINCT source_file), count(_rescued_data) FROM bronze.usajobs_historicjoa
UNION ALL SELECT 'silver.employment', count(*), count(DISTINCT snapshot_month), NULL FROM silver.employment
UNION ALL SELECT 'silver.separations', count(*), count(DISTINCT source_file), NULL FROM silver.separations
UNION ALL SELECT 'silver.accessions', count(*), count(DISTINCT source_file), NULL FROM silver.accessions
UNION ALL SELECT 'silver.job_postings', count(*), count(DISTINCT control_number), NULL FROM silver.job_postings
UNION ALL SELECT 'silver.agency_subelements', count(*), count(DISTINCT agency_subelement_code), NULL FROM silver.agency_subelements
UNION ALL SELECT 'silver.occupational_series', count(*), count(DISTINCT occupational_series_code), NULL FROM silver.occupational_series;

-- COMMAND ----------

SELECT
  (SELECT count(*) FROM bronze.opm_employment WHERE source_file = 'employment_202608_1.parquet') AS employment_202608_rows,  -- 2024832
  (SELECT count(*) FROM bronze.opm_separations WHERE source_file = 'separations_202509_5.parquet') AS separations_202509_rows,  -- 120540
  (SELECT count(*) FROM silver.separations WHERE agency_subelement_code = 'HSBC' AND source_file = 'separations_202608_1.parquet') AS tsa_rows_in_202608_file,  -- 512
  (SELECT count(*) FROM silver.job_postings WHERE opening_status = 'Accepting applications') AS postings_status_accepting,  -- 724
  (SELECT count(*) FROM silver.job_postings WHERE opening_status = 'Accepting applications' AND close_date >= DATE '2026-10-31') AS postings_open_on_pull_day,  -- 427
  (SELECT count(*) FROM silver.job_postings WHERE agency_level = 1) AS postings_department_level;  -- 43

-- COMMAND ----------

-- MAGIC %md **For spec 03.** How far back each file's actions reach, and whether an effective month
-- MAGIC shows up in many files. OPM rows carry no action id, so if the same action is restated in
-- MAGIC later files it cannot be deduplicated; the semantic layer must then count by `source_file`
-- MAGIC (month reported) and say so, or use only rows where the two months agree.

-- COMMAND ----------

SELECT source_file, count(*) AS rows, min(effective_month) AS earliest, max(effective_month) AS latest,
  sum(CASE WHEN effective_month = to_date(regexp_extract(source_file, '_(\\d{6})_', 1), 'yyyyMM') THEN 1 ELSE 0 END) AS rows_effective_in_file_month
FROM silver.separations
GROUP BY source_file
ORDER BY source_file;
