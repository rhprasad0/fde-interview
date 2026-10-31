-- Databricks notebook source
-- MAGIC %md
-- MAGIC # Spec 03: synthetic schema and semantic layer
-- MAGIC
-- MAGIC Builds the agent's only surface. **synthetic** holds imputed copies of the three OPM tables
-- MAGIC (location and pay drawn from USAJOBS DHS postings where OPM redacted them, flagged per row),
-- MAGIC the masking test, and the labeled demo staffing plan. **semantic** holds eight governed views
-- MAGIC and eight table-valued functions over them. Every OPM row with a city gets an approximate
-- MAGIC point from the Census Gazetteer for the spec 05 map. `silver` is read, never written, except
-- MAGIC for the two geocoding lookups this spec owns. Runs once on the SQL warehouse as job
-- MAGIC `workforce-03-semantic`; rerunning replaces every object and reproduces every draw.

-- COMMAND ----------

USE CATALOG workforce;

-- COMMAND ----------

-- MAGIC %md ## Geocoding lookups: Census Gazetteer 2025 places
-- MAGIC
-- MAGIC One interior point per incorporated place or CDP. The gazetteer `NAME` carries a legal
-- MAGIC suffix (`Abbeville city`, `Indianapolis city (balance)`) that OPM's city does not, so the
-- MAGIC suffix is stripped here only; stripping it from OPM's `KANSAS CITY` would break the match.
-- MAGIC `synthetic.place_key` (apostrophes, periods, leading `ST`) is applied to both sides.

-- COMMAND ----------

CREATE OR REPLACE TABLE bronze.census_gazetteer_places
COMMENT 'Census Bureau 2025 Gazetteer national places file as received (pipe-delimited, every column STRING); one row per incorporated place or census-designated place'
AS SELECT *, _metadata.file_name AS source_file
FROM read_files('/Volumes/workforce/bronze/landing/census/', format => 'csv', sep => '|', header => true,
                schemaHints => 'INTPTLAT STRING, INTPTLONG STRING, GEOID STRING, ANSICODE STRING');

-- COMMAND ----------

CREATE OR REPLACE FUNCTION synthetic.place_key(city STRING) RETURNS STRING
COMMENT 'Join key for a city name: upper case, an OPM borough tail dropped (NEW YORK - KINGS), apostrophes and periods dropped, leading ST expanded to SAINT'
RETURN regexp_replace(regexp_replace(regexp_replace(upper(trim(city)), ' - .*$', ''), '[\'.]', ''), '^ST ', 'SAINT ');

-- COMMAND ----------

CREATE OR REPLACE TABLE silver.places
COMMENT 'Approximate city points for maps: Census Gazetteer 2025 interior point per (name, usps); name is the place name upper-cased without its legal suffix, keyed with synthetic.place_key. First GEOID wins on a duplicate name. Owned by spec 03'
AS SELECT name, usps, latitude, longitude
FROM (
  SELECT synthetic.place_key(regexp_replace(upper(NAME),
           ' (CITY AND BOROUGH|CITY|TOWN|VILLAGE|CDP|BOROUGH|MUNICIPALITY|COMUNIDAD|ZONA URBANA|(UNIFIED |CONSOLIDATED |METROPOLITAN |METRO )?GOVERNMENT)?( \\(BALANCE\\))?$', '')) AS name,
    USPS AS usps, CAST(INTPTLAT AS DOUBLE) AS latitude, CAST(INTPTLONG AS DOUBLE) AS longitude,
    GEOID
  FROM bronze.census_gazetteer_places)
QUALIFY row_number() OVER (PARTITION BY name, usps ORDER BY GEOID) = 1;

-- COMMAND ----------

CREATE OR REPLACE TABLE silver.state_centroids
COMMENT 'Fallback point per state or territory: mean latitude and longitude of its Gazetteer places; approximate, for maps only. GU, VI, MP have no Gazetteer places and get a hand-entered island point (places = 0). Owned by spec 03'
AS SELECT usps, avg(latitude) AS latitude, avg(longitude) AS longitude, count(*) AS places
FROM silver.places GROUP BY usps
UNION ALL SELECT * FROM VALUES ('GU', 13.44, 144.79, 0), ('VI', 18.34, -64.90, 0), ('MP', 15.19, 145.75, 0)
  AS t(usps, latitude, longitude, places);

-- COMMAND ----------

-- MAGIC %md ## The pools: USAJOBS DHS postings
-- MAGIC
-- MAGIC Location from posting locations for the same component and series; pay from postings for
-- MAGIC the same component, series, pay plan, and grade. `idx` is a total order within each key, so a
-- MAGIC rerun draws the same posting. The counts twins let each row compute its pick before touching
-- MAGIC a pool, so the pool join is a plain equi-join on key plus `idx`.

-- COMMAND ----------

CREATE OR REPLACE TABLE synthetic.posting_locations
COMMENT 'Location pool for imputation: one row per DHS posting x series x US location with a state. city and state upper-cased to match OPM; idx orders rows within (component, series) by control number, city, state'
AS WITH abbr AS (
  SELECT DISTINCT duty_station_state AS state, duty_station_state_abbreviation AS state_abbreviation
  FROM silver.employment WHERE pay_redacted = false
  UNION SELECT * FROM VALUES ('PUERTO RICO', 'PR'), ('GUAM', 'GU'), ('VIRGIN ISLANDS', 'VI'),
                             ('NORTHERN MARIANA ISLANDS', 'MP') AS t(state, state_abbreviation)),
pl AS (
  SELECT control_number, agency_subelement_code, series,
    upper(trim(loc.positionLocationCity)) AS city, upper(trim(loc.positionLocationState)) AS state
  FROM (SELECT p.*, s AS series FROM silver.job_postings p LATERAL VIEW explode(occupational_series_codes) e AS s) ps
  LATERAL VIEW explode(locations) l AS loc
  WHERE agency_subelement_code IS NOT NULL AND loc.positionLocationCountry = 'United States'
    AND nullif(trim(loc.positionLocationState), '') IS NOT NULL)
SELECT pl.control_number, pl.agency_subelement_code, pl.series, pl.city, pl.state, abbr.state_abbreviation,
  row_number() OVER (PARTITION BY agency_subelement_code, series ORDER BY control_number, city, pl.state) AS idx,
  count(*) OVER (PARTITION BY agency_subelement_code, series) AS n
FROM pl LEFT JOIN abbr ON abbr.state = pl.state;

-- COMMAND ----------

CREATE OR REPLACE TABLE synthetic.posting_location_counts
COMMENT 'Pool size n per (component, series) in synthetic.posting_locations'
AS SELECT agency_subelement_code, series, count(*) AS n FROM synthetic.posting_locations GROUP BY ALL;

-- COMMAND ----------

CREATE OR REPLACE TABLE synthetic.posting_pay
COMMENT 'Pay pool for imputation: one row per DHS posting x series x grade, minimum salary at least 20,000. Numeric grade ranges are expanded; letter ranges keep the minimum only. Grades lpad to two characters to match OPM (09, not 9). idx orders rows within (component, series, pay plan, grade) by control number'
AS WITH g AS (
  SELECT control_number, agency_subelement_code, series, pay_plan_code, minimum_salary, maximum_salary,
    CASE WHEN try_cast(minimum_grade AS INT) IS NOT NULL AND try_cast(maximum_grade AS INT) IS NOT NULL
      THEN transform(sequence(least(CAST(minimum_grade AS INT), CAST(maximum_grade AS INT)),
                              greatest(CAST(minimum_grade AS INT), CAST(maximum_grade AS INT))),
                     x -> lpad(CAST(x AS STRING), 2, '0'))
      ELSE array(lpad(minimum_grade, 2, '0')) END AS grades
  FROM silver.job_postings LATERAL VIEW explode(occupational_series_codes) e AS series
  WHERE agency_subelement_code IS NOT NULL AND minimum_salary >= 20000)
SELECT control_number, agency_subelement_code, series, pay_plan_code, grade, minimum_salary, maximum_salary,
  row_number() OVER (PARTITION BY agency_subelement_code, series, pay_plan_code, grade ORDER BY control_number) AS idx,
  count(*) OVER (PARTITION BY agency_subelement_code, series, pay_plan_code, grade) AS n
FROM g LATERAL VIEW explode(grades) e AS grade;

-- COMMAND ----------

CREATE OR REPLACE TABLE synthetic.posting_pay_counts
COMMENT 'Pool size n per (component, series, pay plan, grade) in synthetic.posting_pay'
AS SELECT agency_subelement_code, series, pay_plan_code, grade, count(*) AS n FROM synthetic.posting_pay GROUP BY ALL;


-- COMMAND ----------

-- MAGIC %md ## The draw
-- MAGIC
-- MAGIC No `rand()`. Each row's pick is a hash of its published columns plus its position among
-- MAGIC identical rows, so a rerun gives the same tables (identical rows are indistinguishable, so
-- MAGIC the multiset is the same even though window order among them is not). `pay_redacted = true`
-- MAGIC marks exactly the rows whose location is redacted, so one flag drives both picks; NULL is
-- MAGIC missing pay, not redaction. Draws are independent per snapshot: OPM rows carry no person id.
-- MAGIC The last stage attaches the approximate point.

-- COMMAND ----------

CREATE OR REPLACE TABLE synthetic.employment
COMMENT 'Synthetic copy of silver.employment. On rows where OPM redacted location and pay, duty station city and state and annualized pay are imputed from USAJOBS DHS postings for the same component and series (and pay plan and grade for pay); see location_imputed, pay_imputed, and the *_source_control_number columns. Postings show where DHS is hiring, not where staff sit. Pay is uniform within the chosen posting range, which overstates spread when the range spans grades. Other redacted columns remain REDACTED. latitude and longitude are the Census Gazetteer interior point of the duty station city (geo_precision = city) or the mean of the state places (geo_precision = state); approximate, for maps only. silver.employment is the published record.'
AS WITH r AS (
  SELECT *, xxhash64(to_json(struct(*))) AS row_hash FROM silver.employment),
d AS (  -- identical rows hash alike; dup_idx spreads their draws
  SELECT *, row_number() OVER (PARTITION BY row_hash ORDER BY row_hash) AS dup_idx FROM r),
k AS (  -- the pick, computed before touching the pools; NULL when not redacted or no pool
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
   AND pc.grade = lpad(d.grade, 2, '0')),
drawn AS (
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
   AND p.pay_plan_code = k.pay_plan_code AND p.grade = lpad(k.grade, 2, '0') AND p.idx = k.pay_pick),
g AS (  -- OPM writes Puerto Rico as state NO DATA REPORTED
  SELECT *, CASE WHEN duty_station_state = 'NO DATA REPORTED' AND duty_station_country_code = 'US' THEN 'PR'
                 ELSE duty_station_state_abbreviation END AS geo_usps
  FROM drawn)
SELECT g.* EXCEPT (geo_usps),
  coalesce(pl.latitude, sc.latitude)   AS latitude,
  coalesce(pl.longitude, sc.longitude) AS longitude,
  CASE WHEN pl.name IS NOT NULL THEN 'city' WHEN sc.usps IS NOT NULL THEN 'state' END AS geo_precision
FROM g
LEFT JOIN silver.places pl ON pl.name = synthetic.place_key(g.duty_station_city) AND pl.usps = g.geo_usps
LEFT JOIN silver.state_centroids sc ON sc.usps = g.geo_usps;

-- COMMAND ----------

CREATE OR REPLACE TABLE synthetic.separations
COMMENT 'Synthetic copy of silver.separations. On rows where OPM redacted location and pay, duty station city and state and annualized pay are imputed from USAJOBS DHS postings for the same component and series (and pay plan and grade for pay); see location_imputed, pay_imputed, and the *_source_control_number columns. Postings show where DHS is hiring, not where staff sit. Pay is uniform within the chosen posting range, which overstates spread when the range spans grades. Other redacted columns remain REDACTED. latitude and longitude are the Census Gazetteer interior point of the duty station city (geo_precision = city) or the mean of the state places (geo_precision = state); approximate, for maps only. silver.separations is the published record.'
AS WITH r AS (
  SELECT *, xxhash64(to_json(struct(*))) AS row_hash FROM silver.separations),
d AS (  -- identical rows hash alike; dup_idx spreads their draws
  SELECT *, row_number() OVER (PARTITION BY row_hash ORDER BY row_hash) AS dup_idx FROM r),
k AS (  -- the pick, computed before touching the pools; NULL when not redacted or no pool
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
   AND pc.grade = lpad(d.grade, 2, '0')),
drawn AS (
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
   AND p.pay_plan_code = k.pay_plan_code AND p.grade = lpad(k.grade, 2, '0') AND p.idx = k.pay_pick),
g AS (  -- OPM writes Puerto Rico as state NO DATA REPORTED
  SELECT *, CASE WHEN duty_station_state = 'NO DATA REPORTED' AND duty_station_country_code = 'US' THEN 'PR'
                 ELSE duty_station_state_abbreviation END AS geo_usps
  FROM drawn)
SELECT g.* EXCEPT (geo_usps),
  coalesce(pl.latitude, sc.latitude)   AS latitude,
  coalesce(pl.longitude, sc.longitude) AS longitude,
  CASE WHEN pl.name IS NOT NULL THEN 'city' WHEN sc.usps IS NOT NULL THEN 'state' END AS geo_precision
FROM g
LEFT JOIN silver.places pl ON pl.name = synthetic.place_key(g.duty_station_city) AND pl.usps = g.geo_usps
LEFT JOIN silver.state_centroids sc ON sc.usps = g.geo_usps;

-- COMMAND ----------

CREATE OR REPLACE TABLE synthetic.accessions
COMMENT 'Synthetic copy of silver.accessions. On rows where OPM redacted location and pay, duty station city and state and annualized pay are imputed from USAJOBS DHS postings for the same component and series (and pay plan and grade for pay); see location_imputed, pay_imputed, and the *_source_control_number columns. Postings show where DHS is hiring, not where staff sit. Pay is uniform within the chosen posting range, which overstates spread when the range spans grades. Other redacted columns remain REDACTED. latitude and longitude are the Census Gazetteer interior point of the duty station city (geo_precision = city) or the mean of the state places (geo_precision = state); approximate, for maps only. silver.accessions is the published record.'
AS WITH r AS (
  SELECT *, xxhash64(to_json(struct(*))) AS row_hash FROM silver.accessions),
d AS (  -- identical rows hash alike; dup_idx spreads their draws
  SELECT *, row_number() OVER (PARTITION BY row_hash ORDER BY row_hash) AS dup_idx FROM r),
k AS (  -- the pick, computed before touching the pools; NULL when not redacted or no pool
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
   AND pc.grade = lpad(d.grade, 2, '0')),
drawn AS (
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
   AND p.pay_plan_code = k.pay_plan_code AND p.grade = lpad(k.grade, 2, '0') AND p.idx = k.pay_pick),
g AS (  -- OPM writes Puerto Rico as state NO DATA REPORTED
  SELECT *, CASE WHEN duty_station_state = 'NO DATA REPORTED' AND duty_station_country_code = 'US' THEN 'PR'
                 ELSE duty_station_state_abbreviation END AS geo_usps
  FROM drawn)
SELECT g.* EXCEPT (geo_usps),
  coalesce(pl.latitude, sc.latitude)   AS latitude,
  coalesce(pl.longitude, sc.longitude) AS longitude,
  CASE WHEN pl.name IS NOT NULL THEN 'city' WHEN sc.usps IS NOT NULL THEN 'state' END AS geo_precision
FROM g
LEFT JOIN silver.places pl ON pl.name = synthetic.place_key(g.duty_station_city) AND pl.usps = g.geo_usps
LEFT JOIN silver.state_centroids sc ON sc.usps = g.geo_usps;

-- COMMAND ----------

-- MAGIC %md ## Masking test (informational)
-- MAGIC
-- MAGIC FEMA (`HSCB`) and CISA (`HSCA`) publish location for most rows. Take their August 2026 rows
-- MAGIC with `pay_redacted = false` (NULL is missing pay, not redaction, and is excluded), run the
-- MAGIC same location draw with redaction forced true, and compare the drawn state to the true one.
-- MAGIC Same hash and `dup_idx` method as the real draw (the hash input includes the published
-- MAGIC location, so a truly redacted twin would draw differently; the distribution is what is tested).
-- MAGIC The number is recorded and disclosed; no result changes the design (Ryan, 2026-10-31). It
-- MAGIC flatters the method: FEMA and CISA hire in a few office cities; TSA and CBP do not.

-- COMMAND ----------

CREATE OR REPLACE TABLE synthetic.imputation_quality
COMMENT 'Masking test of the location imputation, August 2026: FEMA and CISA rows with published location, re-imputed as if redacted. state_match_share is the share of imputed rows whose drawn state equals the published state; state_overlap is the sum over states of the smaller of the published and drawn shares (1 = identical distributions). Informational only; flatters the method, since FEMA and CISA are office-heavy while TSA and CBP spread over hundreds of airports and ports'
AS WITH t AS (
  SELECT *, xxhash64(to_json(struct(*))) AS row_hash FROM silver.employment
  WHERE snapshot_month = DATE'2026-08-01' AND agency_subelement_code IN ('HSCB', 'HSCA') AND pay_redacted = false),
d AS (SELECT *, row_number() OVER (PARTITION BY row_hash ORDER BY row_hash) AS dup_idx FROM t),
m AS (
  SELECT d.agency_subelement_code, d.duty_station_state AS true_state, l.state AS imputed_state
  FROM d
  JOIN synthetic.posting_location_counts lc
    ON lc.agency_subelement_code = d.agency_subelement_code AND lc.series = d.occupational_series_code
  JOIN synthetic.posting_locations l
    ON l.agency_subelement_code = d.agency_subelement_code AND l.series = d.occupational_series_code
   AND l.idx = pmod(xxhash64(d.row_hash, d.dup_idx, 'location'), lc.n) + 1),
true_n AS (SELECT agency_subelement_code, true_state AS state, count(*) AS n FROM m GROUP BY ALL),
imputed_n AS (SELECT agency_subelement_code, imputed_state AS state, count(*) AS n FROM m GROUP BY ALL)
SELECT c.agency_subelement_code, c.agency_subelement, c.rows_tested, i.rows_imputed,
  round(i.state_match_share, 4) AS state_match_share, round(o.overlap_rows / i.rows_imputed, 4) AS state_overlap,
  DATE'2026-08-01' AS snapshot_month
FROM (SELECT agency_subelement_code, any_value(agency_subelement) AS agency_subelement, count(*) AS rows_tested
      FROM t GROUP BY ALL) c
JOIN (SELECT agency_subelement_code, count(*) AS rows_imputed, avg(CAST(true_state = imputed_state AS INT)) AS state_match_share
      FROM m GROUP BY ALL) i USING (agency_subelement_code)
JOIN (SELECT agency_subelement_code, sum(least(true_n.n, imputed_n.n)) AS overlap_rows
      FROM true_n JOIN imputed_n USING (agency_subelement_code, state) GROUP BY ALL) o USING (agency_subelement_code);

-- COMMAND ----------

-- MAGIC %md ## Staffing plan (synthetic)
-- MAGIC
-- MAGIC Component x series x fiscal quarter, FY2026 Q1 to FY2027 Q4, for cells with at least 50
-- MAGIC August 2026 employees. Scaled to OMB Historical Table 16.1 (FY2027 edition), Homeland
-- MAGIC Security: 227,000 FTE (FY2026 estimate) and 224,000 (FY2027 estimate), against 225,574
-- MAGIC August records. Two stress cells (TSA 1802, CBP 1895) are set so FY2026 Q1 to Q3 hiring
-- MAGIC lands 20% under plan. Fiscal quarters coincide with calendar quarters (FY Q1 = Oct to Dec),
-- MAGIC so `trunc(month, 'QUARTER')` is the fiscal quarter start.

-- COMMAND ----------

CREATE OR REPLACE TABLE synthetic.staffing_plan
COMMENT 'Synthetic Annual Staffing Plan for the demo. In deployment this table is the agency ASP submission. One row per component, series, and fiscal quarter FY2026 Q1 to FY2027 Q4, for cells with at least 50 employees in the August 2026 snapshot; generation_rule on every row says how it was made'
AS WITH hc AS (
  SELECT agency_subelement_code, occupational_series_code, count(*) AS headcount
  FROM synthetic.employment WHERE snapshot_month = DATE'2026-08-01' GROUP BY ALL),
total AS (SELECT sum(headcount) AS records FROM hc),
seps AS (
  SELECT agency_subelement_code, occupational_series_code, count(*) AS separations_non_drp
  FROM synthetic.separations
  WHERE effective_month BETWEEN DATE'2025-09-01' AND DATE'2026-08-01' AND drp_indicator <> 'Y'
  GROUP BY ALL),
acc AS (
  SELECT agency_subelement_code, occupational_series_code, trunc(effective_month, 'QUARTER') AS quarter_start,
    count(*) AS accessions
  FROM synthetic.accessions GROUP BY ALL),
q AS (
  SELECT quarter_start, year(add_months(quarter_start, 3)) AS fiscal_year,
    concat('FY', year(add_months(quarter_start, 3)), 'Q', quarter(add_months(quarter_start, 3))) AS fiscal_quarter
  FROM (SELECT explode(sequence(DATE'2025-10-01', DATE'2027-07-01', INTERVAL 3 MONTH)) AS quarter_start)),
b AS (
  SELECT hc.*, q.*, coalesce(s.separations_non_drp, 0) AS separations_non_drp,
    CAST(round(IF(q.fiscal_year = 2026, 227000, 224000) * hc.headcount / total.records) AS INT) AS target_onboard,
    (hc.agency_subelement_code, hc.occupational_series_code) IN (('HSBC', '1802'), ('HSBD', '1895'))
      AND q.fiscal_quarter IN ('FY2026Q1', 'FY2026Q2', 'FY2026Q3') AS stress
  FROM hc CROSS JOIN q CROSS JOIN total
  LEFT JOIN seps s USING (agency_subelement_code, occupational_series_code)
  WHERE hc.headcount >= 50)
SELECT b.agency_subelement_code, b.occupational_series_code, b.fiscal_year, b.fiscal_quarter, b.quarter_start,
  CAST(IF(b.stress, round(coalesce(a.accessions, 0) / 0.8),
          round((b.separations_non_drp + greatest(b.target_onboard - b.headcount, 0)) / 4)) AS INT) AS planned_hires,
  b.target_onboard,
  true AS is_synthetic,
  IF(b.stress,
     'Stress cell: planned_hires = round(accessions effective in the quarter, as known 2026-10-31, / 0.8), so hiring lands 20% under plan. Right-censored: later OPM files add accessions and the variance drifts toward zero. target_onboard as the base rule',
     'Base: target_onboard = OMB Table 16.1 (FY2027 edition) DHS FTE estimate for the fiscal year (227,000 FY2026; 224,000 FY2027; FTE, not headcount) x the cell share of August 2026 headcount (near-uniform scaling, since both sit within 1% of 225,574 records). planned_hires per quarter = (non-DRP separations effective 2025-09 to 2026-08 + max(target_onboard - August 2026 headcount, 0)) / 4'
  ) AS generation_rule
FROM b
LEFT JOIN acc a
  ON a.agency_subelement_code = b.agency_subelement_code AND a.occupational_series_code = b.occupational_series_code
 AND a.quarter_start = b.quarter_start;

-- COMMAND ----------

-- MAGIC %md ## Semantic layer: object types (views)
-- MAGIC
-- MAGIC DHS only, row level, over `synthetic` where it exists and `silver` otherwise. Views read
-- MAGIC their sources with the owner's rights, so the agent needs nothing on `synthetic` or `silver`.

-- COMMAND ----------

CREATE OR REPLACE VIEW semantic.component (
  agency_subelement_code COMMENT 'Component code as OPM and USAJOBS both write it, e.g. HSBC (TSA), HSBD (CBP), HSCB (FEMA)',
  agency_subelement COMMENT 'Component name')
COMMENT 'DHS components (OPM agency subelements) that appear in the employment snapshots'
AS SELECT agency_subelement_code, agency_subelement FROM silver.agency_subelements
WHERE agency_code = 'HS' AND agency_subelement_code IN (SELECT DISTINCT agency_subelement_code FROM silver.employment);

-- COMMAND ----------

CREATE OR REPLACE VIEW semantic.occupation (
  occupational_series_code COMMENT 'Four-digit OPM occupational series, e.g. 1802 (compliance inspection, includes TSA screeners), 1895 (CBP officer)',
  occupational_series COMMENT 'Series name',
  job_family_code COMMENT 'Two-digit job family (the series group)')
COMMENT 'Occupational series code list (USAJOBS), all of government'
AS SELECT occupational_series_code, occupational_series, job_family_code FROM silver.occupational_series;

-- COMMAND ----------

CREATE OR REPLACE VIEW semantic.workforce_snapshot (
  snapshot_month COMMENT 'Month-end snapshot, as first of month; 2025-09-01 to 2026-08-01',
  agency_subelement_code COMMENT 'Component code, e.g. HSBC (TSA)', agency_subelement,
  occupational_series_code COMMENT 'Four-digit occupational series', occupational_series,
  pay_plan_code, grade COMMENT 'OPM grade, zero-padded (09); letters for TSA SV bands; 00 for ES',
  duty_station_city COMMENT 'Duty station city; imputed (synthetic) where location_imputed is true; REDACTED where OPM redacted it and no posting pool exists',
  duty_station_state COMMENT 'Duty station state, upper case; imputed (synthetic) where location_imputed is true',
  duty_station_state_abbreviation,
  latitude COMMENT 'Approximate point for maps only: Census Gazetteer interior point of the city, or the state mean (see geo_precision)',
  longitude COMMENT 'Approximate point for maps only',
  geo_precision COMMENT 'city (Gazetteer place match), state (state-centroid fallback), or NULL (no usable state)',
  tenure, length_of_service_years, age_bracket, supervisory_status, work_schedule,
  annualized_adjusted_basic_pay COMMENT 'Annual pay; imputed (synthetic) where pay_imputed is true, uniform within a matching posting salary range',
  pay_redacted COMMENT 'true where OPM redacted location and pay; NULL means pay is missing, not redacted',
  location_imputed COMMENT 'true where city and state are synthetic, drawn from a USAJOBS posting for the same component and series; label such answers as synthetic',
  pay_imputed COMMENT 'true where pay is synthetic, drawn from a USAJOBS posting for the same component, series, pay plan, and grade',
  location_source_control_number COMMENT 'USAJOBS control number the imputed location came from',
  pay_source_control_number COMMENT 'USAJOBS control number the imputed pay came from',
  source_file COMMENT 'OPM file the row came from, e.g. employment_202608_1.parquet')
COMMENT 'DHS employee records at each month-end snapshot, one row per record (count = 1). OPM redacts location and pay for about three quarters of DHS (law enforcement and security components); where it does, city, state, and pay are imputed from USAJOBS postings and flagged. Postings show where DHS hires, not where staff sit, so location answers on imputed rows are distribution-level only. No person id: rows are not linked across snapshots'
AS SELECT snapshot_month, agency_subelement_code, agency_subelement, occupational_series_code, occupational_series,
  pay_plan_code, grade, duty_station_city, duty_station_state, duty_station_state_abbreviation,
  latitude, longitude, geo_precision, tenure, length_of_service_years, age_bracket, supervisory_status, work_schedule,
  annualized_adjusted_basic_pay, pay_redacted, location_imputed, pay_imputed,
  location_source_control_number, pay_source_control_number, source_file
FROM synthetic.employment;

-- COMMAND ----------

CREATE OR REPLACE VIEW semantic.separation (
  effective_month COMMENT 'Month the separation took effect; count separations by this column',
  reported_month COMMENT 'Month of the OPM file that reported it; can trail effective_month by up to two years',
  separation_category COMMENT 'QUIT, RETIREMENT - VOLUNTARY, RETIREMENT - EARLY OUT, TERMINATION, TRANSFER OUT, and others',
  drp_indicator COMMENT 'Y for the 2025 deferred resignation program (DRP) wave, a one-time event; N otherwise',
  agency_subelement_code, agency_subelement, occupational_series_code, occupational_series, pay_plan_code, grade,
  duty_station_city COMMENT 'Imputed (synthetic) where location_imputed is true',
  duty_station_state COMMENT 'Imputed (synthetic) where location_imputed is true',
  duty_station_state_abbreviation, latitude COMMENT 'Approximate, for maps only', longitude, geo_precision,
  tenure, length_of_service_years, age_bracket, supervisory_status, work_schedule,
  annualized_adjusted_basic_pay COMMENT 'Imputed (synthetic) where pay_imputed is true',
  pay_redacted COMMENT 'true where OPM redacted; NULL is missing, not redacted',
  location_imputed, pay_imputed, location_source_control_number, pay_source_control_number, source_file)
COMMENT 'DHS separations (actions leaving federal service), one row per action, from the twelve monthly OPM files 2025-09 to 2026-08. Count by effective_month across all files. 0.8% of rows are detectable restatements (identical rows in two files); a restatement that changes a column is invisible. Recent months are right-censored: late reports keep arriving, so counts ending in 2026-08 will grow'
AS SELECT effective_month, to_date(regexp_extract(source_file, '_(\\d{6})_', 1), 'yyyyMM') AS reported_month,
  separation_category, drp_indicator, agency_subelement_code, agency_subelement, occupational_series_code,
  occupational_series, pay_plan_code, grade, duty_station_city, duty_station_state, duty_station_state_abbreviation,
  latitude, longitude, geo_precision, tenure, length_of_service_years, age_bracket, supervisory_status, work_schedule,
  annualized_adjusted_basic_pay, pay_redacted, location_imputed, pay_imputed,
  location_source_control_number, pay_source_control_number, source_file
FROM synthetic.separations;

-- COMMAND ----------

CREATE OR REPLACE VIEW semantic.accession (
  effective_month COMMENT 'Month the accession took effect; count accessions by this column',
  reported_month COMMENT 'Month of the OPM file that reported it',
  accession_category COMMENT 'NEW HIRE - COMPETITIVE SERVICE, NEW HIRE - EXCEPTED SERVICE, TRANSFER IN, SES',
  agency_subelement_code, agency_subelement, occupational_series_code, occupational_series, pay_plan_code, grade,
  duty_station_city COMMENT 'Imputed (synthetic) where location_imputed is true',
  duty_station_state COMMENT 'Imputed (synthetic) where location_imputed is true',
  duty_station_state_abbreviation, latitude COMMENT 'Approximate, for maps only', longitude, geo_precision,
  tenure, length_of_service_years, age_bracket, supervisory_status, work_schedule,
  annualized_adjusted_basic_pay COMMENT 'Imputed (synthetic) where pay_imputed is true',
  pay_redacted COMMENT 'true where OPM redacted; NULL is missing, not redacted',
  location_imputed, pay_imputed, location_source_control_number, pay_source_control_number, source_file)
COMMENT 'DHS accessions (new hires and transfers in), one row per action, from the twelve monthly OPM files 2025-09 to 2026-08. Count by effective_month across all files. Identical rows across files (9%) are mostly distinct same-month hires, not restatements. Recent months are right-censored: September 2026 arrives 2026-11-04'
AS SELECT effective_month, to_date(regexp_extract(source_file, '_(\\d{6})_', 1), 'yyyyMM') AS reported_month,
  accession_category, agency_subelement_code, agency_subelement, occupational_series_code,
  occupational_series, pay_plan_code, grade, duty_station_city, duty_station_state, duty_station_state_abbreviation,
  latitude, longitude, geo_precision, tenure, length_of_service_years, age_bracket, supervisory_status, work_schedule,
  annualized_adjusted_basic_pay, pay_redacted, location_imputed, pay_imputed,
  location_source_control_number, pay_source_control_number, source_file
FROM synthetic.accessions;

-- COMMAND ----------

CREATE OR REPLACE VIEW semantic.job_posting
COMMENT 'USAJOBS announcements for DHS components opened 2025-09-01 to 2026-10-31, one row per announcement. Open on a date means open_date <= date AND close_date >= date (opening_status is the status on pull day, 2026-10-31, only); for a past date that is an upper bound, since postings filled or cancelled early are invisible. series is the first listed series; match a series with array_contains(occupational_series_codes, series). total_openings is NULL when the posting says Many or Few (see total_openings_raw)'
AS SELECT *, occupational_series_codes[0] AS series FROM silver.job_postings;

-- COMMAND ----------

CREATE OR REPLACE VIEW semantic.staffing_plan
COMMENT 'SYNTHETIC Annual Staffing Plan for the demo (is_synthetic is always true); in deployment this is the agency ASP submission. Component x series x fiscal quarter FY2026Q1 to FY2027Q4 for cells with 50+ August 2026 employees. generation_rule says how each row was made; TSA 1802 and CBP 1895 FY2026 Q1 to Q3 are stress cells set 20% above actual hiring'
AS SELECT * FROM synthetic.staffing_plan;

-- COMMAND ----------

CREATE OR REPLACE VIEW semantic.imputation_quality
COMMENT 'Masking test of the location imputation (FEMA and CISA, August 2026): how often a drawn state matches the published one. Quote it when a location answer rests on imputed rows; it flatters the method for TSA and CBP'
AS SELECT * FROM synthetic.imputation_quality;

-- COMMAND ----------

-- MAGIC %md ## Semantic layer: metric functions (the graded tools)
-- MAGIC
-- MAGIC Fixed SQL, one per question family; the agent calls these over the MCP functions server and
-- MAGIC never writes SQL. A NULL `component` or `series` means all of DHS. Rules they share, stated in
-- MAGIC each comment: count actions by `effective_month` across all files; trailing twelve months
-- MAGIC (TTM) is effective months `as_of_month - 11` to `as_of_month`; `headcount_start` is the
-- MAGIC snapshot at `as_of_month - 11` and the earliest snapshot is 2025-09, so 2026-08 is the only
-- MAGIC `as_of_month` with a full window; recent months are right-censored. Any day in a month works.

-- COMMAND ----------

CREATE OR REPLACE FUNCTION semantic.headcount(
  as_of_month STRING COMMENT 'Date as YYYY-MM-DD (STRING because Genie trusted assets refuse DATE arguments). Snapshot month, 2025-09-01 to 2026-08-01 (latest); any day in the month works',
  component STRING COMMENT 'Component code, e.g. HSBC (TSA), HSBD (CBP), HSCB (FEMA), HSCA (CISA); NULL for all of DHS',
  series STRING COMMENT 'Four-digit occupational series, e.g. 1802 (TSA screeners), 1895 (CBP officers); NULL for all')
RETURNS TABLE (duty_station_state STRING, headcount BIGINT, headcount_location_imputed BIGINT, source_file STRING)
COMMENT 'Question family 1: how many people a component or occupation has, and in which states. One row per duty station state, largest first. headcount_location_imputed rows have a synthetic state drawn from USAJOBS postings (where DHS hires, not where staff sit); say so when it is a large share, and quote imputation_quality(). source_file is the OPM snapshot file used'
RETURN SELECT duty_station_state, count(*) AS headcount, count_if(location_imputed) AS headcount_location_imputed,
  max(source_file) AS source_file
FROM semantic.workforce_snapshot
WHERE snapshot_month = trunc(to_date(headcount.as_of_month), 'MM')
  AND (headcount.component IS NULL OR agency_subelement_code = headcount.component)
  AND (headcount.series IS NULL OR occupational_series_code = headcount.series)
GROUP BY duty_station_state
ORDER BY headcount DESC;

-- COMMAND ----------

CREATE OR REPLACE FUNCTION semantic.separation_rate(
  as_of_month STRING COMMENT 'Date as YYYY-MM-DD (STRING because Genie trusted assets refuse DATE arguments). Last month of the trailing twelve; only 2026-08-01 has a start snapshot (earlier months return NULL rates)',
  component STRING COMMENT 'Component code, e.g. HSBC (TSA); NULL for all of DHS',
  series STRING COMMENT 'Four-digit occupational series, e.g. 1802; NULL for all')
RETURNS TABLE (headcount_start BIGINT, headcount_end BIGINT, separations_ttm BIGINT, separations_ttm_excl_drp BIGINT,
               quits BIGINT, retirements BIGINT, rate DOUBLE, rate_excl_drp DOUBLE, files_used BIGINT)
COMMENT 'Question family 2: attrition over the trailing twelve months (effective months as_of_month - 11 to as_of_month), with and without the 2025 deferred resignation program (DRP) wave. rate = separations / mean(headcount_start, headcount_end); headcount_start is the snapshot at as_of_month - 11. Separations counted by effective_month across all monthly files (files_used); about 0.8% are detectable restatements. Right-censored: late reports keep arriving, so recent counts will grow'
RETURN WITH hc AS (  -- parameters cannot sit inside an aggregate, so flag the start snapshot first
  SELECT nullif(count_if(is_start), 0) AS s, count_if(NOT is_start) AS e
  FROM (SELECT snapshot_month = add_months(trunc(to_date(separation_rate.as_of_month), 'MM'), -11) AS is_start
        FROM semantic.workforce_snapshot
        WHERE snapshot_month IN (add_months(trunc(to_date(separation_rate.as_of_month), 'MM'), -11), trunc(to_date(separation_rate.as_of_month), 'MM'))
          AND (separation_rate.component IS NULL OR agency_subelement_code = separation_rate.component)
          AND (separation_rate.series IS NULL OR occupational_series_code = separation_rate.series))),
sp AS (
  SELECT count(*) AS t, count_if(drp_indicator <> 'Y') AS x, count_if(separation_category = 'QUIT') AS q,
    count_if(separation_category LIKE 'RETIREMENT%') AS r, count(DISTINCT source_file) AS f
  FROM semantic.separation
  WHERE effective_month BETWEEN add_months(trunc(to_date(separation_rate.as_of_month), 'MM'), -11) AND trunc(to_date(separation_rate.as_of_month), 'MM')
    AND (separation_rate.component IS NULL OR agency_subelement_code = separation_rate.component)
    AND (separation_rate.series IS NULL OR occupational_series_code = separation_rate.series))
SELECT hc.s, hc.e, sp.t, sp.x, sp.q, sp.r,
  round(sp.t / ((hc.s + hc.e) / 2), 4), round(sp.x / ((hc.s + hc.e) / 2), 4), sp.f
FROM hc CROSS JOIN sp;

-- COMMAND ----------

CREATE OR REPLACE FUNCTION semantic.attrition_ranking(
  as_of_month STRING COMMENT 'Date as YYYY-MM-DD (STRING because Genie trusted assets refuse DATE arguments). Last month of the trailing twelve; use 2026-08-01 (the only month with a start snapshot)',
  min_headcount INT COMMENT 'Smallest cell to rank, by headcount at as_of_month, e.g. 100; small cells have noisy rates',
  top_n INT COMMENT 'How many cells to return, e.g. 10')
RETURNS TABLE (rank INT, agency_subelement_code STRING, occupational_series_code STRING, occupational_series STRING,
               headcount_start BIGINT, headcount_end BIGINT, separations_ttm BIGINT, separations_ttm_excl_drp BIGINT,
               quits BIGINT, retirements BIGINT, rate DOUBLE, rate_excl_drp DOUBLE, files_used BIGINT)
COMMENT 'Question family 3: which component x series cells are losing people fastest. Same columns and rules as separation_rate, one row per cell, ranked by rate (highest first). Compare rate with rate_excl_drp: the 2025 DRP wave dominates some cells. Right-censored: recent counts will grow'
RETURN WITH hc AS (  -- parameters cannot sit inside an aggregate, so flag the start snapshot first
  SELECT agency_subelement_code, occupational_series_code, any_value(occupational_series) AS occupational_series,
    nullif(count_if(is_start), 0) AS s, count_if(NOT is_start) AS e
  FROM (SELECT *, snapshot_month = add_months(trunc(to_date(attrition_ranking.as_of_month), 'MM'), -11) AS is_start
        FROM semantic.workforce_snapshot
        WHERE snapshot_month IN (add_months(trunc(to_date(attrition_ranking.as_of_month), 'MM'), -11), trunc(to_date(attrition_ranking.as_of_month), 'MM')))
  GROUP BY agency_subelement_code, occupational_series_code),
sp AS (
  SELECT agency_subelement_code, occupational_series_code, count(*) AS t, count_if(drp_indicator <> 'Y') AS x,
    count_if(separation_category = 'QUIT') AS q, count_if(separation_category LIKE 'RETIREMENT%') AS r,
    count(DISTINCT source_file) AS f
  FROM semantic.separation
  WHERE effective_month BETWEEN add_months(trunc(to_date(attrition_ranking.as_of_month), 'MM'), -11) AND trunc(to_date(attrition_ranking.as_of_month), 'MM')
  GROUP BY agency_subelement_code, occupational_series_code),
c AS (
  SELECT hc.agency_subelement_code, hc.occupational_series_code, hc.occupational_series, hc.s, hc.e,
    coalesce(sp.t, 0) AS t, coalesce(sp.x, 0) AS x, coalesce(sp.q, 0) AS q, coalesce(sp.r, 0) AS r, coalesce(sp.f, 0) AS f,
    round(coalesce(sp.t, 0) / ((hc.s + hc.e) / 2), 4) AS rate, round(coalesce(sp.x, 0) / ((hc.s + hc.e) / 2), 4) AS rate_excl_drp
  FROM hc LEFT JOIN sp USING (agency_subelement_code, occupational_series_code)
  WHERE hc.e >= attrition_ranking.min_headcount)
SELECT * FROM (
  SELECT CAST(row_number() OVER (ORDER BY rate DESC NULLS LAST, agency_subelement_code, occupational_series_code) AS INT) AS rank,
    agency_subelement_code, occupational_series_code, occupational_series, s, e, t, x, q, r, rate, rate_excl_drp, f
  FROM c)
WHERE rank <= attrition_ranking.top_n  -- QUALIFY cannot see a parameter
ORDER BY rank;

-- COMMAND ----------

CREATE OR REPLACE FUNCTION semantic.length_of_service_profile(
  as_of_month STRING COMMENT 'Date as YYYY-MM-DD (STRING because Genie trusted assets refuse DATE arguments). Snapshot month, 2025-09-01 to 2026-08-01 (latest)',
  component STRING COMMENT 'Component code, e.g. HSBC (TSA); NULL for all of DHS',
  series STRING COMMENT 'Four-digit occupational series; NULL for all')
RETURNS TABLE (bucket STRING, headcount BIGINT, share DOUBLE, source_file STRING)
COMMENT 'Question family 4: how tenure-heavy a cell is, and whether a retirement cliff is forming. Headcount by years of federal service in buckets <1, 1-3, 3-5, 5-10, 10-20, 20+ (lower bound inclusive), with each bucket share of the cell. Published OPM values, not imputed. source_file is the snapshot used'
RETURN SELECT bucket, count(*) AS headcount, round(count(*) / sum(count(*)) OVER (), 4) AS share, max(source_file) AS source_file
FROM (
  SELECT source_file, CASE WHEN length_of_service_years < 1 THEN '<1' WHEN length_of_service_years < 3 THEN '1-3'
    WHEN length_of_service_years < 5 THEN '3-5' WHEN length_of_service_years < 10 THEN '5-10'
    WHEN length_of_service_years < 20 THEN '10-20' WHEN length_of_service_years >= 20 THEN '20+' END AS bucket
  FROM semantic.workforce_snapshot
  WHERE snapshot_month = trunc(to_date(length_of_service_profile.as_of_month), 'MM')
    AND (length_of_service_profile.component IS NULL OR agency_subelement_code = length_of_service_profile.component)
    AND (length_of_service_profile.series IS NULL OR occupational_series_code = length_of_service_profile.series))
GROUP BY bucket
ORDER BY array_position(array('<1', '1-3', '3-5', '5-10', '10-20', '20+'), bucket);

-- COMMAND ----------

CREATE OR REPLACE FUNCTION semantic.open_postings(
  as_of_date STRING COMMENT 'Date as YYYY-MM-DD (STRING because Genie trusted assets refuse DATE arguments). Date the postings were open; postings cover 2025-09-01 to 2026-10-31',
  component STRING COMMENT 'Component code, e.g. HSBC (TSA); NULL for all of DHS',
  series STRING COMMENT 'Four-digit occupational series; NULL for all. Matches any series a posting lists')
RETURNS TABLE (control_number STRING, agency_subelement_code STRING, position_title STRING, minimum_grade STRING,
               maximum_grade STRING, total_openings INT, total_openings_raw STRING, states ARRAY<STRING>,
               open_date DATE, close_date DATE)
COMMENT 'Question family 5: what USAJOBS postings are advertised against a cell on a date. Open means open_date <= as_of_date AND close_date >= as_of_date; for a past date that is an upper bound, since postings filled or cancelled before their close date are invisible. total_openings is NULL when the posting says Many or Few (total_openings_raw has the text). Closing soonest first'
RETURN SELECT control_number, agency_subelement_code, position_title, minimum_grade, maximum_grade, total_openings,
  total_openings_raw, array_distinct(transform(locations, l -> l.positionLocationState)) AS states, open_date, close_date
FROM semantic.job_posting
WHERE open_date <= to_date(open_postings.as_of_date) AND close_date >= to_date(open_postings.as_of_date)
  AND (open_postings.component IS NULL OR agency_subelement_code = open_postings.component)
  AND (open_postings.series IS NULL OR array_contains(occupational_series_codes, open_postings.series))
ORDER BY close_date, control_number;

-- COMMAND ----------

CREATE OR REPLACE FUNCTION semantic.posting_coverage(
  as_of_date STRING COMMENT 'Date as YYYY-MM-DD (STRING because Genie trusted assets refuse DATE arguments). Date to count open postings; separations are the twelve effective months ending in its month',
  component STRING COMMENT 'Component code, e.g. HSBD (CBP); NULL for all of DHS',
  series STRING COMMENT 'Four-digit occupational series; NULL for all')
RETURNS TABLE (separations_ttm BIGINT, open_postings BIGINT, openings_known BIGINT, postings_many_or_few BIGINT,
               coverage_ratio DOUBLE, files_used BIGINT)
COMMENT 'Question family 6: is advertised hiring aimed at where people are leaving. separations_ttm counts effective months (month of as_of_date) - 11 to that month across all OPM files (files_used); OPM data ends 2026-08, so later dates see fewer months. open_postings is an upper bound (open_date <= date AND close_date >= date). openings_known sums stated openings; postings_many_or_few say Many or Few and are not in the sum. coverage_ratio = openings_known / separations_ttm. Right-censored'
RETURN WITH sp AS (
  SELECT count(*) AS n, count(DISTINCT source_file) AS f FROM semantic.separation
  WHERE effective_month BETWEEN add_months(trunc(to_date(posting_coverage.as_of_date), 'MM'), -11) AND trunc(to_date(posting_coverage.as_of_date), 'MM')
    AND (posting_coverage.component IS NULL OR agency_subelement_code = posting_coverage.component)
    AND (posting_coverage.series IS NULL OR occupational_series_code = posting_coverage.series)),
po AS (
  SELECT count(*) AS n, sum(total_openings) AS known, count_if(total_openings IS NULL) AS vague FROM semantic.job_posting
  WHERE open_date <= to_date(posting_coverage.as_of_date) AND close_date >= to_date(posting_coverage.as_of_date)
    AND (posting_coverage.component IS NULL OR agency_subelement_code = posting_coverage.component)
    AND (posting_coverage.series IS NULL OR array_contains(occupational_series_codes, posting_coverage.series)))
SELECT sp.n, po.n, coalesce(po.known, 0), po.vague, round(coalesce(po.known, 0) / nullif(sp.n, 0), 4), sp.f
FROM sp CROSS JOIN po;

-- COMMAND ----------

CREATE OR REPLACE FUNCTION semantic.plan_variance(
  fiscal_quarter STRING COMMENT 'Fiscal quarter as FY2026Q1 (Oct to Dec 2025) through FY2027Q4; accessions exist through FY2026Q4 (July and August only)',
  component STRING COMMENT 'Component code, e.g. HSBD (CBP); NULL for every planned cell',
  series STRING COMMENT 'Four-digit occupational series; NULL for all')
RETURNS TABLE (planned_hires BIGINT, actual_accessions BIGINT, variance BIGINT, variance_pct DOUBLE,
               is_synthetic BOOLEAN, generation_rule STRING, cells BIGINT, files_used BIGINT)
COMMENT 'Question family 7: how a quarter of hiring landed against the staffing plan, and why. The plan is SYNTHETIC (is_synthetic, generation_rule say how it was made); say so. actual_accessions counts accessions effective in the quarter in the planned cells, across all OPM files (files_used). variance = actual - planned; variance_pct = variance / planned. TSA 1802 and CBP 1895 FY2026 Q1 to Q3 are stress cells. Right-censored: later files add accessions'
RETURN WITH p AS (
  SELECT * FROM semantic.staffing_plan
  WHERE fiscal_quarter = upper(plan_variance.fiscal_quarter)
    AND (plan_variance.component IS NULL OR agency_subelement_code = plan_variance.component)
    AND (plan_variance.series IS NULL OR occupational_series_code = plan_variance.series)),
a AS (
  SELECT a.source_file FROM semantic.accession a
  JOIN p ON a.agency_subelement_code = p.agency_subelement_code AND a.occupational_series_code = p.occupational_series_code
   AND trunc(a.effective_month, 'QUARTER') = p.quarter_start),
pp AS (
  SELECT sum(planned_hires) AS planned, bool_and(is_synthetic) AS syn,
    array_join(array_sort(collect_set(generation_rule)), ' | ') AS rule, count(*) AS cells FROM p),
aa AS (SELECT count(*) AS actual, count(DISTINCT source_file) AS f FROM a)
SELECT pp.planned, aa.actual, aa.actual - pp.planned, round((aa.actual - pp.planned) / pp.planned, 4),
  pp.syn, pp.rule, pp.cells, aa.f
FROM pp CROSS JOIN aa;

-- COMMAND ----------

CREATE OR REPLACE FUNCTION semantic.imputation_quality()
RETURNS TABLE (agency_subelement_code STRING, agency_subelement STRING, rows_tested BIGINT, rows_imputed BIGINT,
               state_match_share DOUBLE, state_overlap DOUBLE, snapshot_month DATE)
COMMENT 'Question family 8: how much to trust a location answer that rests on imputed rows. Masking test: FEMA and CISA August 2026 rows with published location were re-imputed as if redacted; state_match_share is how often the drawn state equals the true one, state_overlap how similar the two state distributions are (1 = identical). It flatters the method for TSA and CBP, whose staff spread over hundreds of airports and ports. Quote it with any imputed-location answer'
RETURN SELECT agency_subelement_code, agency_subelement, rows_tested, rows_imputed,
  CAST(state_match_share AS DOUBLE), CAST(state_overlap AS DOUBLE), snapshot_month
FROM semantic.imputation_quality;

-- COMMAND ----------

-- MAGIC %md ## Cleanup
-- MAGIC
-- MAGIC Spec 01 step 5's smoke objects; the functions above replace them.

-- COMMAND ----------

DROP FUNCTION IF EXISTS semantic.headcount_for;

-- COMMAND ----------

DROP TABLE IF EXISTS silver.smoke;

-- COMMAND ----------

-- MAGIC %md ## Checks (spec 03 step 7)
-- MAGIC
-- MAGIC Expected, measured on silver 2026-10-31: synthetic employment 2,725,190, separations
-- MAGIC 27,799, accessions 25,852; August 2026 has 171,627 redacted rows, `location_imputed` on
-- MAGIC exactly 171,296, `pay_imputed` on exactly 162,812, and no imputed row that is not redacted.
-- MAGIC City-precision share at least 85% of rows with a usable state, none of them NULL. 210 plan
-- MAGIC cells x 8 quarters, 6 stress rows, FY2027 Q1 targets near 216,500. TSA 1802 separation rate
-- MAGIC uses 12 files with `rate_excl_drp < rate`; CBP 1895 FY2026 Q1 variance near -20%.

-- COMMAND ----------

SELECT
  (SELECT count(*) FROM synthetic.employment) AS employment_rows,     -- 2725190
  (SELECT count(*) FROM synthetic.separations) AS separation_rows,    -- 27799
  (SELECT count(*) FROM synthetic.accessions) AS accession_rows,      -- 25852
  count_if(pay_redacted) AS aug_redacted,                             -- 171627
  count_if(location_imputed) AS aug_location_imputed,                 -- 171296
  count_if(pay_imputed) AS aug_pay_imputed,                           -- 162812
  count_if((location_imputed OR pay_imputed) AND pay_redacted IS DISTINCT FROM true) AS imputed_not_redacted  -- 0
FROM synthetic.employment WHERE snapshot_month = DATE'2026-08-01';

-- COMMAND ----------

SELECT location_imputed, count(*) AS rows_with_usable_state,
  round(count_if(geo_precision = 'city') / count(*), 4) AS city_share,  -- >= 0.85
  count_if(geo_precision IS NULL) AS no_point,                           -- 0
  (SELECT count(*) FROM silver.places) AS places, (SELECT count(*) FROM silver.state_centroids) AS centroids
FROM synthetic.employment
WHERE snapshot_month = DATE'2026-08-01' AND duty_station_state NOT IN ('REDACTED', 'INVALID')
  AND NOT (duty_station_state = 'NO DATA REPORTED' AND duty_station_country_code <> 'US')
GROUP BY location_imputed;

-- COMMAND ----------

SELECT count(*) AS plan_rows,                                                           -- 1680
  count(DISTINCT agency_subelement_code, occupational_series_code) AS plan_cells,       -- 210
  count_if(generation_rule LIKE 'Stress%') AS stress_rows,                              -- 6
  sum(target_onboard) FILTER (WHERE fiscal_quarter = 'FY2027Q1') AS fy2027q1_target,    -- about 216500
  bool_and(is_synthetic) AS all_synthetic
FROM synthetic.staffing_plan;

-- COMMAND ----------

SELECT 'separation_rate TSA 1802' AS check, to_json(struct(*)) AS result
FROM semantic.separation_rate('2026-08-01', 'HSBC', '1802')   -- files_used 12, rate_excl_drp < rate
UNION ALL
SELECT 'plan_variance CBP 1895 FY2026Q1', to_json(struct(* EXCEPT (generation_rule)))
FROM semantic.plan_variance('FY2026Q1', 'HSBD', '1895')           -- variance_pct near -0.20, is_synthetic
UNION ALL
SELECT 'imputation_quality ' || agency_subelement_code, to_json(struct(*)) FROM semantic.imputation_quality();

-- COMMAND ----------

-- MAGIC %md **Determinism.** Compare this hash across two runs of the job: headcount and summed pay by
-- MAGIC component, series, and (imputed) state for August 2026.

-- COMMAND ----------

SELECT sha2(array_join(array_sort(collect_list(concat_ws('|', agency_subelement_code, occupational_series_code,
  duty_station_state, CAST(n AS STRING), CAST(pay AS STRING)))), ','), 256) AS august_2026_hash
FROM (SELECT agency_subelement_code, occupational_series_code, duty_station_state, count(*) AS n,
        sum(CAST(round(annualized_adjusted_basic_pay) AS BIGINT)) AS pay  -- integer sum: order-independent
      FROM synthetic.employment WHERE snapshot_month = DATE'2026-08-01' GROUP BY ALL);
