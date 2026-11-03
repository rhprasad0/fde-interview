-- Spec 06: DuckDB port of notebooks/03_semantic.sql, the table-building half (geocoding lookups, the pools, the
-- draw, the masking test, the staffing plan). The views and functions live in Postgres (03_semantic.pg.sql).
-- Same design as the Databricks build; the hash is md5 instead of xxhash64, so imputed rows differ in which
-- posting they draw but every count that depends only on pool existence reproduces.

-- Geocoding lookups: Census Gazetteer 2025 places. The 'g' flag matters: Spark replaced every apostrophe and
-- period, DuckDB and Postgres replace the first only without it.
CREATE OR REPLACE MACRO place_key(city) AS
  regexp_replace(regexp_replace(regexp_replace(upper(trim(city)), ' - .*$', ''), '[''.]', '', 'g'), '^ST ', 'SAINT ');

CREATE OR REPLACE TABLE silver.places AS
SELECT name, usps, latitude, longitude
FROM (
  SELECT place_key(regexp_replace(upper(NAME),
           ' (CITY AND BOROUGH|CITY|TOWN|VILLAGE|CDP|BOROUGH|MUNICIPALITY|COMUNIDAD|ZONA URBANA|(UNIFIED |CONSOLIDATED |METROPOLITAN |METRO )?GOVERNMENT)?( \(BALANCE\))?$', '')) AS name,
    USPS AS usps, CAST(INTPTLAT AS DOUBLE) AS latitude, CAST(INTPTLONG AS DOUBLE) AS longitude,
    GEOID
  FROM bronze.census_gazetteer_places)
QUALIFY row_number() OVER (PARTITION BY name, usps ORDER BY GEOID) = 1;

CREATE OR REPLACE TABLE silver.state_centroids AS
SELECT usps, round(avg(latitude), 6) AS latitude, round(avg(longitude), 6) AS longitude, count(*) AS places  -- rounded: a parallel avg sums in varying order
FROM silver.places GROUP BY usps
UNION ALL SELECT * FROM (VALUES ('GU', 13.44, 144.79, 0), ('VI', 18.34, -64.90, 0), ('MP', 15.19, 145.75, 0))
  AS t(usps, latitude, longitude, places);

-- The pools: USAJOBS DHS postings. idx is a total order within each key, so a rerun draws the same posting.
CREATE OR REPLACE TABLE synthetic.posting_locations AS
WITH abbr AS (
  SELECT DISTINCT duty_station_state AS state, duty_station_state_abbreviation AS state_abbreviation
  FROM silver.employment WHERE pay_redacted = false
  UNION SELECT * FROM (VALUES ('PUERTO RICO', 'PR'), ('GUAM', 'GU'), ('VIRGIN ISLANDS', 'VI'),
                              ('NORTHERN MARIANA ISLANDS', 'MP')) AS t(state, state_abbreviation)),
pl AS (
  SELECT control_number, agency_subelement_code, series,
    upper(trim(loc.positionLocationCity)) AS city, upper(trim(loc.positionLocationState)) AS state
  FROM (SELECT ps.*, unnest(locations) AS loc
        FROM (SELECT p.*, unnest(occupational_series_codes) AS series FROM silver.job_postings p) ps)
  WHERE agency_subelement_code IS NOT NULL AND loc.positionLocationCountry = 'United States'
    AND nullif(trim(loc.positionLocationState), '') IS NOT NULL)
SELECT pl.control_number, pl.agency_subelement_code, pl.series, pl.city, pl.state, abbr.state_abbreviation,
  row_number() OVER (PARTITION BY agency_subelement_code, series ORDER BY control_number, city, pl.state) AS idx,
  count(*) OVER (PARTITION BY agency_subelement_code, series) AS n
FROM pl LEFT JOIN abbr ON abbr.state = pl.state;

CREATE OR REPLACE TABLE synthetic.posting_location_counts AS
SELECT agency_subelement_code, series, count(*) AS n FROM synthetic.posting_locations GROUP BY ALL;

CREATE OR REPLACE TABLE synthetic.posting_pay AS
WITH g AS (
  SELECT control_number, agency_subelement_code, series, pay_plan_code, minimum_salary, maximum_salary,
    CASE WHEN try_cast(minimum_grade AS INT) IS NOT NULL AND try_cast(maximum_grade AS INT) IS NOT NULL
      THEN list_transform(generate_series(least(CAST(minimum_grade AS INT), CAST(maximum_grade AS INT)),
                                          greatest(CAST(minimum_grade AS INT), CAST(maximum_grade AS INT))),
                          lambda x: lpad(CAST(x AS VARCHAR), 2, '0'))
      ELSE [lpad(minimum_grade, 2, '0')] END AS grades
  FROM (SELECT p.*, unnest(occupational_series_codes) AS series FROM silver.job_postings p)
  WHERE agency_subelement_code IS NOT NULL AND minimum_salary >= 20000)
SELECT control_number, agency_subelement_code, series, pay_plan_code, grade, minimum_salary, maximum_salary,
  row_number() OVER (PARTITION BY agency_subelement_code, series, pay_plan_code, grade ORDER BY control_number) AS idx,
  count(*) OVER (PARTITION BY agency_subelement_code, series, pay_plan_code, grade) AS n
FROM (SELECT g.*, unnest(grades) AS grade FROM g);

CREATE OR REPLACE TABLE synthetic.posting_pay_counts AS
SELECT agency_subelement_code, series, pay_plan_code, grade, count(*) AS n FROM synthetic.posting_pay GROUP BY ALL;

-- The draw. No rand(): each row's pick is a hash of its published columns plus its position among identical
-- rows, so a rerun gives the same tables. md5_number_lower is the low 64 bits of MD5, version-stable and
-- non-negative, so % equals Spark's pmod.
CREATE OR REPLACE MACRO pick(s, n) AS (md5_number_lower(s) % n::UBIGINT)::BIGINT + 1;

CREATE OR REPLACE TABLE synthetic.employment AS
WITH r AS (
  SELECT e.*, md5(to_json(e)) AS row_hash FROM silver.employment e),
d AS (  -- identical rows hash alike; dup_idx spreads their draws
  SELECT *, row_number() OVER (PARTITION BY row_hash ORDER BY row_hash) AS dup_idx FROM r),
k AS (  -- the pick, computed before touching the pools; NULL when not redacted or no pool
  SELECT d.*,
    pick(d.row_hash || '|' || d.dup_idx || '|location', lc.n)             AS loc_pick,
    pick(d.row_hash || '|' || d.dup_idx || '|pay', pc.n)                  AS pay_pick,
    (md5_number_lower(d.row_hash || '|' || d.dup_idx || '|u') % 10000) / 10000.0 AS pay_u
  FROM d
  LEFT JOIN synthetic.posting_location_counts lc
    ON d.pay_redacted AND lc.agency_subelement_code = d.agency_subelement_code
   AND lc.series = d.occupational_series_code
  LEFT JOIN synthetic.posting_pay_counts pc
    ON d.pay_redacted AND pc.agency_subelement_code = d.agency_subelement_code
   AND pc.series = d.occupational_series_code AND pc.pay_plan_code = d.pay_plan_code
   AND pc.grade = lpad(d.grade, 2, '0')),
drawn AS (
  SELECT k.* EXCLUDE (row_hash, dup_idx, loc_pick, pay_pick, pay_u, duty_station_city,
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
SELECT g.* EXCLUDE (geo_usps),
  coalesce(pl.latitude, sc.latitude)   AS latitude,
  coalesce(pl.longitude, sc.longitude) AS longitude,
  CASE WHEN pl.name IS NOT NULL THEN 'city' WHEN sc.usps IS NOT NULL THEN 'state' END AS geo_precision
FROM g
LEFT JOIN silver.places pl ON pl.name = place_key(g.duty_station_city) AND pl.usps = g.geo_usps
LEFT JOIN silver.state_centroids sc ON sc.usps = g.geo_usps;

CREATE OR REPLACE TABLE synthetic.separations AS
WITH r AS (
  SELECT e.*, md5(to_json(e)) AS row_hash FROM silver.separations e),
d AS (
  SELECT *, row_number() OVER (PARTITION BY row_hash ORDER BY row_hash) AS dup_idx FROM r),
k AS (
  SELECT d.*,
    pick(d.row_hash || '|' || d.dup_idx || '|location', lc.n)             AS loc_pick,
    pick(d.row_hash || '|' || d.dup_idx || '|pay', pc.n)                  AS pay_pick,
    (md5_number_lower(d.row_hash || '|' || d.dup_idx || '|u') % 10000) / 10000.0 AS pay_u
  FROM d
  LEFT JOIN synthetic.posting_location_counts lc
    ON d.pay_redacted AND lc.agency_subelement_code = d.agency_subelement_code
   AND lc.series = d.occupational_series_code
  LEFT JOIN synthetic.posting_pay_counts pc
    ON d.pay_redacted AND pc.agency_subelement_code = d.agency_subelement_code
   AND pc.series = d.occupational_series_code AND pc.pay_plan_code = d.pay_plan_code
   AND pc.grade = lpad(d.grade, 2, '0')),
drawn AS (
  SELECT k.* EXCLUDE (row_hash, dup_idx, loc_pick, pay_pick, pay_u, duty_station_city,
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
g AS (
  SELECT *, CASE WHEN duty_station_state = 'NO DATA REPORTED' AND duty_station_country_code = 'US' THEN 'PR'
                 ELSE duty_station_state_abbreviation END AS geo_usps
  FROM drawn)
SELECT g.* EXCLUDE (geo_usps),
  coalesce(pl.latitude, sc.latitude)   AS latitude,
  coalesce(pl.longitude, sc.longitude) AS longitude,
  CASE WHEN pl.name IS NOT NULL THEN 'city' WHEN sc.usps IS NOT NULL THEN 'state' END AS geo_precision
FROM g
LEFT JOIN silver.places pl ON pl.name = place_key(g.duty_station_city) AND pl.usps = g.geo_usps
LEFT JOIN silver.state_centroids sc ON sc.usps = g.geo_usps;

CREATE OR REPLACE TABLE synthetic.accessions AS
WITH r AS (
  SELECT e.*, md5(to_json(e)) AS row_hash FROM silver.accessions e),
d AS (
  SELECT *, row_number() OVER (PARTITION BY row_hash ORDER BY row_hash) AS dup_idx FROM r),
k AS (
  SELECT d.*,
    pick(d.row_hash || '|' || d.dup_idx || '|location', lc.n)             AS loc_pick,
    pick(d.row_hash || '|' || d.dup_idx || '|pay', pc.n)                  AS pay_pick,
    (md5_number_lower(d.row_hash || '|' || d.dup_idx || '|u') % 10000) / 10000.0 AS pay_u
  FROM d
  LEFT JOIN synthetic.posting_location_counts lc
    ON d.pay_redacted AND lc.agency_subelement_code = d.agency_subelement_code
   AND lc.series = d.occupational_series_code
  LEFT JOIN synthetic.posting_pay_counts pc
    ON d.pay_redacted AND pc.agency_subelement_code = d.agency_subelement_code
   AND pc.series = d.occupational_series_code AND pc.pay_plan_code = d.pay_plan_code
   AND pc.grade = lpad(d.grade, 2, '0')),
drawn AS (
  SELECT k.* EXCLUDE (row_hash, dup_idx, loc_pick, pay_pick, pay_u, duty_station_city,
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
g AS (
  SELECT *, CASE WHEN duty_station_state = 'NO DATA REPORTED' AND duty_station_country_code = 'US' THEN 'PR'
                 ELSE duty_station_state_abbreviation END AS geo_usps
  FROM drawn)
SELECT g.* EXCLUDE (geo_usps),
  coalesce(pl.latitude, sc.latitude)   AS latitude,
  coalesce(pl.longitude, sc.longitude) AS longitude,
  CASE WHEN pl.name IS NOT NULL THEN 'city' WHEN sc.usps IS NOT NULL THEN 'state' END AS geo_precision
FROM g
LEFT JOIN silver.places pl ON pl.name = place_key(g.duty_station_city) AND pl.usps = g.geo_usps
LEFT JOIN silver.state_centroids sc ON sc.usps = g.geo_usps;

-- Masking test (informational): FEMA and CISA August 2026 rows with published location, re-drawn as if redacted.
CREATE OR REPLACE TABLE synthetic.imputation_quality AS
WITH t AS (
  SELECT e.*, md5(to_json(e)) AS row_hash FROM silver.employment e
  WHERE snapshot_month = DATE'2026-08-01' AND agency_subelement_code IN ('HSCB', 'HSCA') AND pay_redacted = false),
d AS (SELECT *, row_number() OVER (PARTITION BY row_hash ORDER BY row_hash) AS dup_idx FROM t),
m AS (
  SELECT d.agency_subelement_code, d.duty_station_state AS true_state, l.state AS imputed_state
  FROM d
  JOIN synthetic.posting_location_counts lc
    ON lc.agency_subelement_code = d.agency_subelement_code AND lc.series = d.occupational_series_code
  JOIN synthetic.posting_locations l
    ON l.agency_subelement_code = d.agency_subelement_code AND l.series = d.occupational_series_code
   AND l.idx = pick(d.row_hash || '|' || d.dup_idx || '|location', lc.n)),
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

-- Staffing plan (synthetic): component x series x fiscal quarter, FY2026 Q1 to FY2027 Q4, cells with at least 50
-- August 2026 employees, scaled to OMB Table 16.1 DHS FTE; two stress cells land 20% under plan.
CREATE OR REPLACE TABLE synthetic.staffing_plan AS
WITH hc AS (
  SELECT agency_subelement_code, occupational_series_code, count(*) AS headcount
  FROM synthetic.employment WHERE snapshot_month = DATE'2026-08-01' GROUP BY ALL),
total AS (SELECT sum(headcount) AS records FROM hc),
seps AS (
  SELECT agency_subelement_code, occupational_series_code, count(*) AS separations_non_drp
  FROM synthetic.separations
  WHERE effective_month BETWEEN DATE'2025-09-01' AND DATE'2026-08-01' AND drp_indicator <> 'Y'
  GROUP BY ALL),
acc AS (
  SELECT agency_subelement_code, occupational_series_code, date_trunc('quarter', effective_month)::DATE AS quarter_start,
    count(*) AS accessions
  FROM synthetic.accessions GROUP BY ALL),
q AS (
  SELECT quarter_start, year((quarter_start + INTERVAL 3 MONTH)::DATE) AS fiscal_year,
    concat('FY', year((quarter_start + INTERVAL 3 MONTH)::DATE), 'Q', quarter((quarter_start + INTERVAL 3 MONTH)::DATE)) AS fiscal_quarter
  FROM (SELECT unnest(generate_series(DATE'2025-10-01', DATE'2027-07-01', INTERVAL 3 MONTH))::DATE AS quarter_start)),
b AS (
  SELECT hc.*, q.*, coalesce(s.separations_non_drp, 0) AS separations_non_drp,
    CAST(round(IF(q.fiscal_year = 2026, 227000, 224000) * hc.headcount / total.records) AS INT) AS target_onboard,
    ((hc.agency_subelement_code = 'HSBC' AND hc.occupational_series_code = '1802')
      OR (hc.agency_subelement_code = 'HSBD' AND hc.occupational_series_code = '1895'))
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
