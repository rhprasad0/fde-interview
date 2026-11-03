-- Spec 06: DuckDB port of notebooks/02_load.sql (bronze and silver), run by scripts/load_postgres.py.
-- Bronze is views over the landing files (whole government, every OPM column VARCHAR, plus source_file);
-- nothing whole-government is materialised or shipped. Silver filters to DHS, casts, and renames USAJOBS
-- fields to OPM names. The path comes from the `data` variable the loader sets.

CREATE SCHEMA IF NOT EXISTS bronze;
CREATE SCHEMA IF NOT EXISTS silver;
CREATE SCHEMA IF NOT EXISTS synthetic;

CREATE OR REPLACE VIEW bronze.opm_employment AS
SELECT * EXCLUDE (filename), parse_filename(filename) AS source_file
FROM read_parquet(getvariable('data') || '/opm/employment/*.parquet', filename = true);

CREATE OR REPLACE VIEW bronze.opm_separations AS
SELECT * EXCLUDE (filename), parse_filename(filename) AS source_file
FROM read_parquet(getvariable('data') || '/opm/separations/*.parquet', filename = true);

CREATE OR REPLACE VIEW bronze.opm_accessions AS
SELECT * EXCLUDE (filename), parse_filename(filename) AS source_file
FROM read_parquet(getvariable('data') || '/opm/accessions/*.parquet', filename = true);

CREATE OR REPLACE VIEW bronze.usajobs_historicjoa AS
SELECT * EXCLUDE (filename), parse_filename(filename) AS source_file
FROM read_json(getvariable('data') || '/usajobs/historicjoa/*.json', format = 'newline_delimited',
               union_by_name = true, sample_size = -1, filename = true);

CREATE OR REPLACE VIEW bronze.usajobs_agencysubelements AS
SELECT * FROM read_json(getvariable('data') || '/usajobs/codelist/agencysubelements.json', format = 'newline_delimited');

CREATE OR REPLACE VIEW bronze.usajobs_occupationalseries AS
SELECT * FROM read_json(getvariable('data') || '/usajobs/codelist/occupationalseries.json', format = 'newline_delimited');

CREATE OR REPLACE VIEW bronze.census_gazetteer_places AS
SELECT * EXCLUDE (filename), parse_filename(filename) AS source_file
FROM read_csv(getvariable('data') || '/census/2025_Gaz_place_national.txt', delim = '|', header = true,
              all_varchar = true, filename = true);

-- Silver: DHS only, typed. count is always 1; pay is the literal REDACTED on some rows, so numeric casts use
-- try_cast and pay_redacted keeps the distinction; yyyymm fields become first-of-month dates.

CREATE OR REPLACE TABLE silver.employment AS
SELECT * EXCLUDE ("count", length_of_service_years, annualized_adjusted_basic_pay),
  CAST("count" AS INT) AS "count",
  try_cast(length_of_service_years AS DOUBLE) AS length_of_service_years,
  try_cast(annualized_adjusted_basic_pay AS DOUBLE) AS annualized_adjusted_basic_pay,
  annualized_adjusted_basic_pay = 'REDACTED' AS pay_redacted,
  strptime(snapshot_yyyymm, '%Y%m')::DATE AS snapshot_month
FROM bronze.opm_employment
WHERE agency_code = 'HS';

CREATE OR REPLACE TABLE silver.separations AS
SELECT * EXCLUDE ("count", length_of_service_years, annualized_adjusted_basic_pay),
  CAST("count" AS INT) AS "count",
  try_cast(length_of_service_years AS DOUBLE) AS length_of_service_years,
  try_cast(annualized_adjusted_basic_pay AS DOUBLE) AS annualized_adjusted_basic_pay,
  annualized_adjusted_basic_pay = 'REDACTED' AS pay_redacted,
  strptime(personnel_action_effective_date_yyyymm, '%Y%m')::DATE AS effective_month
FROM bronze.opm_separations
WHERE agency_code = 'HS';

CREATE OR REPLACE TABLE silver.accessions AS
SELECT * EXCLUDE ("count", length_of_service_years, annualized_adjusted_basic_pay),
  CAST("count" AS INT) AS "count",
  try_cast(length_of_service_years AS DOUBLE) AS length_of_service_years,
  try_cast(annualized_adjusted_basic_pay AS DOUBLE) AS annualized_adjusted_basic_pay,
  annualized_adjusted_basic_pay = 'REDACTED' AS pay_redacted,
  strptime(personnel_action_effective_date_yyyymm, '%Y%m')::DATE AS effective_month
FROM bronze.opm_accessions
WHERE agency_code = 'HS';

-- Nested columns stay LIST/STRUCT here (the pools unnest them); the loader ships them to Postgres as JSON text.
CREATE OR REPLACE TABLE silver.job_postings AS
SELECT
  CAST(usajobsControlNumber AS VARCHAR)                        AS control_number,
  announcementNumber                                           AS announcement_number,
  hiringDepartmentCode                                         AS agency_code,
  agencyLevel                                                  AS agency_level,
  IF(agencyLevel = 1, NULL, hiringAgencyCode)                  AS agency_subelement_code,
  hiringAgencyName                                             AS agency_subelement,
  hiringSubelementName                                         AS hiring_office,
  positionTitle                                                AS position_title,
  list_transform(jobcategories, lambda c: c.series)            AS occupational_series_codes,
  positionlocations                                            AS locations,
  CAST(minimumGrade AS VARCHAR)                                AS minimum_grade,
  CAST(maximumGrade AS VARCHAR)                                AS maximum_grade,
  payScale                                                     AS pay_plan_code,
  try_cast(minimumSalary AS DOUBLE)                            AS minimum_salary,
  try_cast(maximumSalary AS DOUBLE)                            AS maximum_salary,
  try_cast(totalOpenings AS INT)                               AS total_openings,
  CAST(totalOpenings AS VARCHAR)                               AS total_openings_raw,
  positionOpenDate::DATE                                       AS open_date,
  positionCloseDate::DATE                                      AS close_date,
  positionExpireDate::DATE                                     AS expire_date,
  positionOpeningStatus                                        AS opening_status,
  list_transform(hiringpaths, lambda h: h.hiringPath)          AS hiring_paths,
  CAST(whoMayApply AS VARCHAR)                                 AS who_may_apply,
  teleworkEligible                                             AS telework_eligible,
  securityClearance                                            AS security_clearance,
  source_file
FROM bronze.usajobs_historicjoa;

CREATE OR REPLACE TABLE silver.agency_subelements AS
SELECT Code AS agency_subelement_code, Value AS agency_subelement, ParentCode AS agency_code,
  IsDisabled = 'Yes' AS is_disabled
FROM bronze.usajobs_agencysubelements;

CREATE OR REPLACE TABLE silver.occupational_series AS
SELECT Code AS occupational_series_code, Value AS occupational_series, JobFamily AS job_family_code,
  IsDisabled = 'Yes' AS is_disabled
FROM bronze.usajobs_occupationalseries;
