-- Spec 06: the semantic layer on Postgres, ported from notebooks/03_semantic.sql L393-689.
-- Eight views and eight table functions over the tables load_postgres.py ships. Rerunnable:
--   psql -f challenge/sql/03_semantic.pg.sql      (as the master user, after load_postgres.py)
-- Spark to Postgres rules used throughout: integer division truncates here, so every rate is
-- numeric before the division and double precision after; count_if is count(*) FILTER; the three
-- nested posting columns are jsonb; parameters are text (YYYY-MM-DD, FY2026Q1, NULL for all) and
-- are cast inside, always qualified as function.param because a column name wins over a parameter.

-- The loader ships the nested JOA columns as JSON text; convert once (guarded so reruns pass).
DO $$ BEGIN
  IF EXISTS (SELECT FROM information_schema.columns WHERE table_schema = 'silver' AND table_name = 'job_postings'
             AND column_name = 'locations' AND data_type <> 'jsonb') THEN
    ALTER TABLE silver.job_postings
      ALTER COLUMN locations TYPE jsonb USING locations::jsonb,
      ALTER COLUMN occupational_series_codes TYPE jsonb USING occupational_series_codes::jsonb,
      ALTER COLUMN hiring_paths TYPE jsonb USING hiring_paths::jsonb;
  END IF;
END $$;

-- Every function and most one-off queries filter on month, component, and series; without these a
-- scan of synthetic.employment (2.7M rows) under sixteen eval workers overran the agent role's 30 s
-- statement_timeout on a db.t4g.micro (smoke, 2026-11-02).
CREATE INDEX IF NOT EXISTS employment_month_cell ON synthetic.employment (snapshot_month, agency_subelement_code, occupational_series_code);
CREATE INDEX IF NOT EXISTS separations_month_cell ON synthetic.separations (effective_month, agency_subelement_code, occupational_series_code);
CREATE INDEX IF NOT EXISTS accessions_month_cell ON synthetic.accessions (effective_month, agency_subelement_code, occupational_series_code);
CREATE INDEX IF NOT EXISTS employment_cell_month ON synthetic.employment (agency_subelement_code, occupational_series_code, snapshot_month);
ANALYZE synthetic.employment; ANALYZE synthetic.separations; ANALYZE synthetic.accessions;

-- ---------------------------------------------------------------------------------------------
-- Views (object types). They read their sources with the owner's rights, so the agent needs
-- nothing on synthetic or silver.
-- ---------------------------------------------------------------------------------------------

CREATE OR REPLACE VIEW semantic.component (agency_subelement_code, agency_subelement) AS
SELECT agency_subelement_code, agency_subelement FROM silver.agency_subelements
WHERE agency_code = 'HS' AND agency_subelement_code IN (SELECT DISTINCT agency_subelement_code FROM synthetic.employment);
COMMENT ON VIEW semantic.component IS 'DHS components (OPM agency subelements) that appear in the employment snapshots';
COMMENT ON COLUMN semantic.component.agency_subelement_code IS 'Component code as OPM and USAJOBS both write it, e.g. HSBC (TSA), HSBD (CBP), HSCB (FEMA)';
COMMENT ON COLUMN semantic.component.agency_subelement IS 'Component name';

CREATE OR REPLACE VIEW semantic.occupation (occupational_series_code, occupational_series, job_family_code) AS
SELECT occupational_series_code, occupational_series, job_family_code FROM silver.occupational_series;
COMMENT ON VIEW semantic.occupation IS 'Occupational series code list (USAJOBS), all of government';
COMMENT ON COLUMN semantic.occupation.occupational_series_code IS 'Four-digit OPM occupational series, e.g. 1802 (compliance inspection, includes TSA screeners), 1895 (CBP officer)';
COMMENT ON COLUMN semantic.occupation.occupational_series IS 'Series name';
COMMENT ON COLUMN semantic.occupation.job_family_code IS 'Two-digit job family (the series group)';

CREATE OR REPLACE VIEW semantic.workforce_snapshot AS
SELECT snapshot_month, agency_subelement_code, agency_subelement, occupational_series_code, occupational_series,
  pay_plan_code, grade, duty_station_city, duty_station_state, duty_station_state_abbreviation,
  latitude, longitude, geo_precision, tenure, length_of_service_years, age_bracket, supervisory_status, work_schedule,
  annualized_adjusted_basic_pay, pay_redacted, location_imputed, pay_imputed,
  location_source_control_number, pay_source_control_number, source_file
FROM synthetic.employment;
COMMENT ON VIEW semantic.workforce_snapshot IS 'DHS employee records at each month-end snapshot, one row per record (count = 1). OPM redacts location and pay for about three quarters of DHS (law enforcement and security components); where it does, city, state, and pay are imputed from USAJOBS postings and flagged. Postings show where DHS hires, not where staff sit, so location answers on imputed rows are distribution-level only. No person id: rows are not linked across snapshots';
COMMENT ON COLUMN semantic.workforce_snapshot.snapshot_month IS 'Month-end snapshot, as first of month; 2025-09-01 to 2026-08-01';
COMMENT ON COLUMN semantic.workforce_snapshot.agency_subelement_code IS 'Component code, e.g. HSBC (TSA)';
COMMENT ON COLUMN semantic.workforce_snapshot.occupational_series_code IS 'Four-digit occupational series';
COMMENT ON COLUMN semantic.workforce_snapshot.grade IS 'OPM grade, zero-padded (09); letters for TSA SV bands; 00 for ES';
COMMENT ON COLUMN semantic.workforce_snapshot.duty_station_city IS 'Duty station city; imputed (synthetic) where location_imputed is true; REDACTED where OPM redacted it and no posting pool exists';
COMMENT ON COLUMN semantic.workforce_snapshot.duty_station_state IS 'Duty station state, upper case; imputed (synthetic) where location_imputed is true';
COMMENT ON COLUMN semantic.workforce_snapshot.latitude IS 'Approximate point for maps only: Census Gazetteer interior point of the city, or the state mean (see geo_precision)';
COMMENT ON COLUMN semantic.workforce_snapshot.longitude IS 'Approximate point for maps only';
COMMENT ON COLUMN semantic.workforce_snapshot.geo_precision IS 'city (Gazetteer place match), state (state-centroid fallback), or NULL (no usable state)';
COMMENT ON COLUMN semantic.workforce_snapshot.annualized_adjusted_basic_pay IS 'Annual pay; imputed (synthetic) where pay_imputed is true, uniform within a matching posting salary range';
COMMENT ON COLUMN semantic.workforce_snapshot.pay_redacted IS 'true where OPM redacted location and pay; NULL means pay is missing, not redacted';
COMMENT ON COLUMN semantic.workforce_snapshot.location_imputed IS 'true where city and state are synthetic, drawn from a USAJOBS posting for the same component and series; label such answers as synthetic';
COMMENT ON COLUMN semantic.workforce_snapshot.pay_imputed IS 'true where pay is synthetic, drawn from a USAJOBS posting for the same component, series, pay plan, and grade';
COMMENT ON COLUMN semantic.workforce_snapshot.location_source_control_number IS 'USAJOBS control number the imputed location came from';
COMMENT ON COLUMN semantic.workforce_snapshot.pay_source_control_number IS 'USAJOBS control number the imputed pay came from';
COMMENT ON COLUMN semantic.workforce_snapshot.source_file IS 'OPM file the row came from, e.g. employment_202608_1.parquet';

CREATE OR REPLACE VIEW semantic.separation AS
SELECT effective_month, to_date(substring(source_file from '_(\d{6})_'), 'YYYYMM') AS reported_month,
  separation_category, drp_indicator, agency_subelement_code, agency_subelement, occupational_series_code,
  occupational_series, pay_plan_code, grade, duty_station_city, duty_station_state, duty_station_state_abbreviation,
  latitude, longitude, geo_precision, tenure, length_of_service_years, age_bracket, supervisory_status, work_schedule,
  annualized_adjusted_basic_pay, pay_redacted, location_imputed, pay_imputed,
  location_source_control_number, pay_source_control_number, source_file
FROM synthetic.separations;
COMMENT ON VIEW semantic.separation IS 'DHS separations (actions leaving federal service), one row per action, from the twelve monthly OPM files 2025-09 to 2026-08. Count by effective_month across all files. 0.8% of rows are detectable restatements (identical rows in two files); a restatement that changes a column is invisible. Recent months are right-censored: late reports keep arriving, so counts ending in 2026-08 will grow';
COMMENT ON COLUMN semantic.separation.effective_month IS 'Month the separation took effect; count separations by this column';
COMMENT ON COLUMN semantic.separation.reported_month IS 'Month of the OPM file that reported it; can trail effective_month by up to two years';
COMMENT ON COLUMN semantic.separation.separation_category IS 'QUIT, RETIREMENT - VOLUNTARY, RETIREMENT - EARLY OUT, TERMINATION, TRANSFER OUT, and others';
COMMENT ON COLUMN semantic.separation.drp_indicator IS 'Y for the 2025 deferred resignation program (DRP) wave, a one-time event; N otherwise';
COMMENT ON COLUMN semantic.separation.duty_station_city IS 'Imputed (synthetic) where location_imputed is true';
COMMENT ON COLUMN semantic.separation.duty_station_state IS 'Imputed (synthetic) where location_imputed is true';
COMMENT ON COLUMN semantic.separation.latitude IS 'Approximate, for maps only';
COMMENT ON COLUMN semantic.separation.annualized_adjusted_basic_pay IS 'Imputed (synthetic) where pay_imputed is true';
COMMENT ON COLUMN semantic.separation.pay_redacted IS 'true where OPM redacted; NULL is missing, not redacted';

CREATE OR REPLACE VIEW semantic.accession AS
SELECT effective_month, to_date(substring(source_file from '_(\d{6})_'), 'YYYYMM') AS reported_month,
  accession_category, agency_subelement_code, agency_subelement, occupational_series_code,
  occupational_series, pay_plan_code, grade, duty_station_city, duty_station_state, duty_station_state_abbreviation,
  latitude, longitude, geo_precision, tenure, length_of_service_years, age_bracket, supervisory_status, work_schedule,
  annualized_adjusted_basic_pay, pay_redacted, location_imputed, pay_imputed,
  location_source_control_number, pay_source_control_number, source_file
FROM synthetic.accessions;
COMMENT ON VIEW semantic.accession IS 'DHS accessions (new hires and transfers in), one row per action, from the twelve monthly OPM files 2025-09 to 2026-08. Count by effective_month across all files. Identical rows across files (9%) are mostly distinct same-month hires, not restatements. Recent months are right-censored: September 2026 arrives 2026-11-04';
COMMENT ON COLUMN semantic.accession.effective_month IS 'Month the accession took effect; count accessions by this column';
COMMENT ON COLUMN semantic.accession.reported_month IS 'Month of the OPM file that reported it';
COMMENT ON COLUMN semantic.accession.accession_category IS 'NEW HIRE - COMPETITIVE SERVICE, NEW HIRE - EXCEPTED SERVICE, TRANSFER IN, SES';
COMMENT ON COLUMN semantic.accession.duty_station_city IS 'Imputed (synthetic) where location_imputed is true';
COMMENT ON COLUMN semantic.accession.duty_station_state IS 'Imputed (synthetic) where location_imputed is true';
COMMENT ON COLUMN semantic.accession.latitude IS 'Approximate, for maps only';
COMMENT ON COLUMN semantic.accession.annualized_adjusted_basic_pay IS 'Imputed (synthetic) where pay_imputed is true';
COMMENT ON COLUMN semantic.accession.pay_redacted IS 'true where OPM redacted; NULL is missing, not redacted';

CREATE OR REPLACE VIEW semantic.job_posting AS
SELECT p.*, p.occupational_series_codes ->> 0 AS series FROM silver.job_postings p;
COMMENT ON VIEW semantic.job_posting IS 'USAJOBS announcements for DHS components opened 2025-09-01 to 2026-10-31, one row per announcement. Open on a date means open_date <= date AND close_date >= date (opening_status is the status on pull day, 2026-10-31, only); for a past date that is an upper bound, since postings filled or cancelled early are invisible. series is the first listed series; occupational_series_codes is a jsonb array, match a series with occupational_series_codes ? series. locations is a jsonb array of {positionLocationCity, positionLocationState, positionLocationCountry}. total_openings is NULL when the posting says Many or Few (see total_openings_raw)';

CREATE OR REPLACE VIEW semantic.staffing_plan AS SELECT * FROM synthetic.staffing_plan;
COMMENT ON VIEW semantic.staffing_plan IS 'SYNTHETIC Annual Staffing Plan for the demo (is_synthetic is always true); in deployment this is the agency ASP submission. Component x series x fiscal quarter FY2026Q1 to FY2027Q4 for cells with 50+ August 2026 employees. generation_rule says how each row was made; TSA 1802 and CBP 1895 FY2026 Q1 to Q3 are stress cells set 20% above actual hiring';

CREATE OR REPLACE VIEW semantic.imputation_quality AS SELECT * FROM synthetic.imputation_quality;
COMMENT ON VIEW semantic.imputation_quality IS 'Masking test of the location imputation (FEMA and CISA, August 2026): how often a drawn state matches the published one. Quote it when a location answer rests on imputed rows; it flatters the method for TSA and CBP';

-- ---------------------------------------------------------------------------------------------
-- Metric functions (the graded tools). Fixed SQL, one per question family. A NULL component or
-- series means all of DHS. Rules they share: count actions by effective_month across all files;
-- trailing twelve months (TTM) is effective months as_of_month - 11 to as_of_month; headcount_start
-- is the snapshot at as_of_month - 11 and the earliest snapshot is 2025-09, so 2026-08 is the only
-- as_of_month with a full window; recent months are right-censored. Any day in a month works.
-- DROP before CREATE: CREATE OR REPLACE cannot change a RETURNS TABLE signature.
-- ---------------------------------------------------------------------------------------------

DROP FUNCTION IF EXISTS semantic.headcount(text, text, text);
CREATE FUNCTION semantic.headcount(as_of_month text, component text, series text)
RETURNS TABLE (duty_station_state text, headcount bigint, headcount_location_imputed bigint, source_file text)
LANGUAGE sql STABLE AS $$
  SELECT duty_station_state, count(*), count(*) FILTER (WHERE location_imputed), max(source_file)
  FROM semantic.workforce_snapshot
  WHERE snapshot_month = date_trunc('month', headcount.as_of_month::date)::date
    AND (headcount.component IS NULL OR agency_subelement_code = headcount.component)
    AND (headcount.series IS NULL OR occupational_series_code = headcount.series)
  GROUP BY duty_station_state
  ORDER BY 2 DESC, 1
$$;
COMMENT ON FUNCTION semantic.headcount(text, text, text) IS 'Question family 1: how many people a component or occupation has, and in which states. One row per duty station state, largest first. headcount_location_imputed rows have a synthetic state drawn from USAJOBS postings (where DHS hires, not where staff sit); say so when it is a large share, and quote imputation_quality(). source_file is the OPM snapshot file used. Parameters: as_of_month, date as YYYY-MM-DD, snapshot month 2025-09-01 to 2026-08-01 (latest), any day in the month works; component, component code e.g. HSBC (TSA), HSBD (CBP), HSCB (FEMA), HSCA (CISA), NULL for all of DHS; series, four-digit occupational series e.g. 1802 (TSA screeners), 1895 (CBP officers), NULL for all';

DROP FUNCTION IF EXISTS semantic.separation_rate(text, text, text);
CREATE FUNCTION semantic.separation_rate(as_of_month text, component text, series text)
RETURNS TABLE (headcount_start bigint, headcount_end bigint, separations_ttm bigint, separations_ttm_excl_drp bigint,
               quits bigint, retirements bigint, rate double precision, rate_excl_drp double precision, files_used bigint)
LANGUAGE sql STABLE AS $$
  WITH m AS (
    SELECT date_trunc('month', separation_rate.as_of_month::date)::date AS e,
           (date_trunc('month', separation_rate.as_of_month::date) - interval '11 months')::date AS s),
  hc AS (
    SELECT nullif(count(*) FILTER (WHERE w.snapshot_month = m.s), 0) AS s, count(*) FILTER (WHERE w.snapshot_month = m.e) AS e
    FROM semantic.workforce_snapshot w, m
    WHERE w.snapshot_month IN (m.s, m.e)
      AND (separation_rate.component IS NULL OR w.agency_subelement_code = separation_rate.component)
      AND (separation_rate.series IS NULL OR w.occupational_series_code = separation_rate.series)),
  sp AS (
    SELECT count(*) AS t, count(*) FILTER (WHERE sep.drp_indicator <> 'Y') AS x,
      count(*) FILTER (WHERE sep.separation_category = 'QUIT') AS q,
      count(*) FILTER (WHERE sep.separation_category LIKE 'RETIREMENT%') AS r, count(DISTINCT sep.source_file) AS f
    FROM semantic.separation sep, m
    WHERE sep.effective_month BETWEEN m.s AND m.e
      AND (separation_rate.component IS NULL OR sep.agency_subelement_code = separation_rate.component)
      AND (separation_rate.series IS NULL OR sep.occupational_series_code = separation_rate.series))
  SELECT hc.s, hc.e, sp.t, sp.x, sp.q, sp.r,
    round(sp.t::numeric / ((hc.s + hc.e) / 2.0), 4)::double precision,
    round(sp.x::numeric / ((hc.s + hc.e) / 2.0), 4)::double precision, sp.f
  FROM hc CROSS JOIN sp
$$;
COMMENT ON FUNCTION semantic.separation_rate(text, text, text) IS 'Question family 2: attrition over the trailing twelve months (effective months as_of_month - 11 to as_of_month), with and without the 2025 deferred resignation program (DRP) wave. rate = separations / mean(headcount_start, headcount_end); headcount_start is the snapshot at as_of_month - 11. Separations counted by effective_month across all monthly files (files_used); about 0.8% are detectable restatements. Right-censored: late reports keep arriving, so recent counts will grow. Parameters: as_of_month, date as YYYY-MM-DD, last month of the trailing twelve, only 2026-08-01 has a start snapshot (earlier months return NULL rates); component, component code e.g. HSBC (TSA), NULL for all of DHS; series, four-digit occupational series e.g. 1802, NULL for all';

DROP FUNCTION IF EXISTS semantic.attrition_ranking(text, int, int);
CREATE FUNCTION semantic.attrition_ranking(as_of_month text, min_headcount int, top_n int)
RETURNS TABLE (rank int, agency_subelement_code text, occupational_series_code text, occupational_series text,
               headcount_start bigint, headcount_end bigint, separations_ttm bigint, separations_ttm_excl_drp bigint,
               quits bigint, retirements bigint, rate double precision, rate_excl_drp double precision, files_used bigint)
LANGUAGE sql STABLE AS $$
  WITH m AS (
    SELECT date_trunc('month', attrition_ranking.as_of_month::date)::date AS e,
           (date_trunc('month', attrition_ranking.as_of_month::date) - interval '11 months')::date AS s),
  hc AS (
    SELECT w.agency_subelement_code, w.occupational_series_code, any_value(w.occupational_series) AS occupational_series,
      nullif(count(*) FILTER (WHERE w.snapshot_month = m.s), 0) AS s, count(*) FILTER (WHERE w.snapshot_month = m.e) AS e
    FROM semantic.workforce_snapshot w, m
    WHERE w.snapshot_month IN (m.s, m.e)
    GROUP BY w.agency_subelement_code, w.occupational_series_code),
  sp AS (
    SELECT sep.agency_subelement_code, sep.occupational_series_code, count(*) AS t,
      count(*) FILTER (WHERE sep.drp_indicator <> 'Y') AS x, count(*) FILTER (WHERE sep.separation_category = 'QUIT') AS q,
      count(*) FILTER (WHERE sep.separation_category LIKE 'RETIREMENT%') AS r, count(DISTINCT sep.source_file) AS f
    FROM semantic.separation sep, m
    WHERE sep.effective_month BETWEEN m.s AND m.e
    GROUP BY sep.agency_subelement_code, sep.occupational_series_code),
  c AS (
    SELECT hc.agency_subelement_code, hc.occupational_series_code, hc.occupational_series, hc.s, hc.e,
      coalesce(sp.t, 0) AS t, coalesce(sp.x, 0) AS x, coalesce(sp.q, 0) AS q, coalesce(sp.r, 0) AS r, coalesce(sp.f, 0) AS f,
      round(coalesce(sp.t, 0)::numeric / ((hc.s + hc.e) / 2.0), 4)::double precision AS rate,
      round(coalesce(sp.x, 0)::numeric / ((hc.s + hc.e) / 2.0), 4)::double precision AS rate_excl_drp
    FROM hc LEFT JOIN sp USING (agency_subelement_code, occupational_series_code)
    WHERE hc.e >= attrition_ranking.min_headcount)
  SELECT * FROM (
    SELECT CAST(row_number() OVER (ORDER BY c.rate DESC NULLS LAST, c.agency_subelement_code, c.occupational_series_code) AS int) AS rank,
      c.agency_subelement_code, c.occupational_series_code, c.occupational_series, c.s, c.e, c.t, c.x, c.q, c.r, c.rate, c.rate_excl_drp, c.f
    FROM c) ranked
  WHERE ranked.rank <= attrition_ranking.top_n
  ORDER BY ranked.rank
$$;
COMMENT ON FUNCTION semantic.attrition_ranking(text, int, int) IS 'Question family 3: which component x series cells are losing people fastest. Same columns and rules as separation_rate, one row per cell, ranked by rate (highest first). Compare rate with rate_excl_drp: the 2025 DRP wave dominates some cells. Right-censored: recent counts will grow. Parameters: as_of_month, date as YYYY-MM-DD, last month of the trailing twelve, use 2026-08-01 (the only month with a start snapshot); min_headcount, smallest cell to rank by headcount at as_of_month, e.g. 100, small cells have noisy rates; top_n, how many cells to return, e.g. 10';

DROP FUNCTION IF EXISTS semantic.length_of_service_profile(text, text, text);
CREATE FUNCTION semantic.length_of_service_profile(as_of_month text, component text, series text)
RETURNS TABLE (bucket text, headcount bigint, share double precision, source_file text)
LANGUAGE sql STABLE AS $$
  SELECT b.bucket, count(*), round(count(*)::numeric / sum(count(*)) OVER (), 4)::double precision, max(b.source_file)
  FROM (
    SELECT source_file, CASE WHEN length_of_service_years < 1 THEN '<1' WHEN length_of_service_years < 3 THEN '1-3'
      WHEN length_of_service_years < 5 THEN '3-5' WHEN length_of_service_years < 10 THEN '5-10'
      WHEN length_of_service_years < 20 THEN '10-20' WHEN length_of_service_years >= 20 THEN '20+' END AS bucket
    FROM semantic.workforce_snapshot
    WHERE snapshot_month = date_trunc('month', length_of_service_profile.as_of_month::date)::date
      AND (length_of_service_profile.component IS NULL OR agency_subelement_code = length_of_service_profile.component)
      AND (length_of_service_profile.series IS NULL OR occupational_series_code = length_of_service_profile.series)) b
  GROUP BY b.bucket
  ORDER BY array_position(ARRAY['<1', '1-3', '3-5', '5-10', '10-20', '20+'], b.bucket)
$$;
COMMENT ON FUNCTION semantic.length_of_service_profile(text, text, text) IS 'Question family 4: how tenure-heavy a cell is, and whether a retirement cliff is forming. Headcount by years of federal service in buckets <1, 1-3, 3-5, 5-10, 10-20, 20+ (lower bound inclusive), with each bucket share of the cell. Published OPM values, not imputed. source_file is the snapshot used. Parameters: as_of_month, date as YYYY-MM-DD, snapshot month 2025-09-01 to 2026-08-01 (latest); component, component code e.g. HSBC (TSA), NULL for all of DHS; series, four-digit occupational series, NULL for all';

DROP FUNCTION IF EXISTS semantic.open_postings(text, text, text);
CREATE FUNCTION semantic.open_postings(as_of_date text, component text, series text)
RETURNS TABLE (control_number text, agency_subelement_code text, position_title text, minimum_grade text,
               maximum_grade text, total_openings int, total_openings_raw text, states text[],
               open_date date, close_date date)
LANGUAGE sql STABLE AS $$
  SELECT control_number, agency_subelement_code, position_title, minimum_grade, maximum_grade, total_openings,
    total_openings_raw,
    ARRAY(SELECT DISTINCT l.v ->> 'positionLocationState' FROM jsonb_array_elements(locations) AS l(v) ORDER BY 1),
    open_date, close_date
  FROM semantic.job_posting
  WHERE open_date <= open_postings.as_of_date::date AND close_date >= open_postings.as_of_date::date
    AND (open_postings.component IS NULL OR agency_subelement_code = open_postings.component)
    AND (open_postings.series IS NULL OR occupational_series_codes ? open_postings.series)
  ORDER BY close_date, control_number
$$;
COMMENT ON FUNCTION semantic.open_postings(text, text, text) IS 'Question family 5: what USAJOBS postings are advertised against a cell on a date. Open means open_date <= as_of_date AND close_date >= as_of_date; for a past date that is an upper bound, since postings filled or cancelled before their close date are invisible. total_openings is NULL when the posting says Many or Few (total_openings_raw has the text). Closing soonest first. Parameters: as_of_date, date as YYYY-MM-DD the postings were open, postings cover 2025-09-01 to 2026-10-31; component, component code e.g. HSBC (TSA), NULL for all of DHS; series, four-digit occupational series, NULL for all, matches any series a posting lists';

DROP FUNCTION IF EXISTS semantic.posting_coverage(text, text, text);
CREATE FUNCTION semantic.posting_coverage(as_of_date text, component text, series text)
RETURNS TABLE (separations_ttm bigint, open_postings bigint, openings_known bigint, postings_many_or_few bigint,
               coverage_ratio double precision, files_used bigint)
LANGUAGE sql STABLE AS $$
  WITH m AS (
    SELECT date_trunc('month', posting_coverage.as_of_date::date)::date AS e,
           (date_trunc('month', posting_coverage.as_of_date::date) - interval '11 months')::date AS s),
  sp AS (
    SELECT count(*) AS n, count(DISTINCT sep.source_file) AS f FROM semantic.separation sep, m
    WHERE sep.effective_month BETWEEN m.s AND m.e
      AND (posting_coverage.component IS NULL OR sep.agency_subelement_code = posting_coverage.component)
      AND (posting_coverage.series IS NULL OR sep.occupational_series_code = posting_coverage.series)),
  po AS (
    SELECT count(*) AS n, sum(p.total_openings) AS known, count(*) FILTER (WHERE p.total_openings IS NULL) AS vague
    FROM semantic.job_posting p
    WHERE p.open_date <= posting_coverage.as_of_date::date AND p.close_date >= posting_coverage.as_of_date::date
      AND (posting_coverage.component IS NULL OR p.agency_subelement_code = posting_coverage.component)
      AND (posting_coverage.series IS NULL OR p.occupational_series_codes ? posting_coverage.series))
  SELECT sp.n, po.n, coalesce(po.known, 0), po.vague,
    round(coalesce(po.known, 0)::numeric / nullif(sp.n, 0), 4)::double precision, sp.f
  FROM sp CROSS JOIN po
$$;
COMMENT ON FUNCTION semantic.posting_coverage(text, text, text) IS 'Question family 6: is advertised hiring aimed at where people are leaving. separations_ttm counts effective months (month of as_of_date) - 11 to that month across all OPM files (files_used); OPM data ends 2026-08, so later dates see fewer months. open_postings is an upper bound (open_date <= date AND close_date >= date). openings_known sums stated openings; postings_many_or_few say Many or Few and are not in the sum. coverage_ratio = openings_known / separations_ttm. Right-censored. Parameters: as_of_date, date as YYYY-MM-DD to count open postings, separations are the twelve effective months ending in its month; component, component code e.g. HSBD (CBP), NULL for all of DHS; series, four-digit occupational series, NULL for all';

DROP FUNCTION IF EXISTS semantic.plan_variance(text, text, text);
CREATE FUNCTION semantic.plan_variance(fiscal_quarter text, component text, series text)
RETURNS TABLE (planned_hires bigint, actual_accessions bigint, variance bigint, variance_pct double precision,
               is_synthetic boolean, generation_rule text, cells bigint, files_used bigint)
LANGUAGE sql STABLE AS $$
  WITH p AS (
    SELECT * FROM semantic.staffing_plan sp
    WHERE sp.fiscal_quarter = upper(plan_variance.fiscal_quarter)
      AND (plan_variance.component IS NULL OR sp.agency_subelement_code = plan_variance.component)
      AND (plan_variance.series IS NULL OR sp.occupational_series_code = plan_variance.series)),
  a AS (
    SELECT a.source_file FROM semantic.accession a
    JOIN p ON a.agency_subelement_code = p.agency_subelement_code AND a.occupational_series_code = p.occupational_series_code
     AND date_trunc('quarter', a.effective_month)::date = p.quarter_start),
  pp AS (
    SELECT sum(p.planned_hires) AS planned, bool_and(p.is_synthetic) AS syn,
      string_agg(DISTINCT p.generation_rule, ' | ' ORDER BY p.generation_rule) AS rule, count(*) AS cells FROM p),
  aa AS (SELECT count(*) AS actual, count(DISTINCT a.source_file) AS f FROM a)
  SELECT pp.planned, aa.actual, aa.actual - pp.planned,
    round((aa.actual - pp.planned)::numeric / nullif(pp.planned, 0), 4)::double precision,
    pp.syn, pp.rule, pp.cells, aa.f
  FROM pp CROSS JOIN aa
$$;
COMMENT ON FUNCTION semantic.plan_variance(text, text, text) IS 'Question family 7: how a quarter of hiring landed against the staffing plan, and why. The plan is SYNTHETIC (is_synthetic, generation_rule say how it was made); say so. actual_accessions counts accessions effective in the quarter in the planned cells, across all OPM files (files_used). variance = actual - planned; variance_pct = variance / planned. TSA 1802 and CBP 1895 FY2026 Q1 to Q3 are stress cells. Right-censored: later files add accessions. Parameters: fiscal_quarter, as FY2026Q1 (Oct to Dec 2025) through FY2027Q4, accessions exist through FY2026Q4 (July and August only); component, component code e.g. HSBD (CBP), NULL for every planned cell; series, four-digit occupational series, NULL for all';

DROP FUNCTION IF EXISTS semantic.imputation_quality();
CREATE FUNCTION semantic.imputation_quality()
RETURNS TABLE (agency_subelement_code text, agency_subelement text, rows_tested bigint, rows_imputed bigint,
               state_match_share double precision, state_overlap double precision, snapshot_month date)
LANGUAGE sql STABLE AS $$
  SELECT q.agency_subelement_code, q.agency_subelement, q.rows_tested, q.rows_imputed,
    q.state_match_share::double precision, q.state_overlap::double precision, q.snapshot_month
  FROM semantic.imputation_quality q
$$;
COMMENT ON FUNCTION semantic.imputation_quality() IS 'Question family 8: how much to trust a location answer that rests on imputed rows. Masking test: FEMA and CISA August 2026 rows with published location were re-imputed as if redacted; state_match_share is how often the drawn state equals the true one, state_overlap how similar the two state distributions are (1 = identical). It flatters the method for TSA and CBP, whose staff spread over hundreds of airports and ports. Quote it with any imputed-location answer. Parameters: none';

-- ---------------------------------------------------------------------------------------------
-- The agent's fence: the views and functions in semantic, nothing else. Reruns re-grant.
-- ---------------------------------------------------------------------------------------------
GRANT SELECT ON ALL TABLES IN SCHEMA semantic TO agent;
REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA semantic FROM PUBLIC;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA semantic TO agent;
