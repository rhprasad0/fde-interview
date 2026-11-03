-- Spec 06 acceptance: the draw-independent numbers from specs/02-results.md and specs/03-results.md.
--   psql -f challenge/sql/checks.pg.sql      (as the master user, after 03_semantic.pg.sql)
-- The DO block raises on the first failing ASSERT, naming the check. Draw-dependent values
-- (imputation_quality shares, imputed states, the determinism hash) are printed, not asserted:
-- record the hash in the journal and require a second load_postgres.py run to reproduce it.

DO $$
DECLARE n bigint; k bigint; x numeric; r record;
BEGIN
  -- silver (02-results, check cells 1 and 2)
  SELECT count(*) INTO n FROM silver.job_postings;
  ASSERT n = 13136, 'job_postings rows: ' || n;
  SELECT count(DISTINCT control_number) INTO n FROM silver.job_postings;
  ASSERT n = 13136, 'job_postings distinct control numbers: ' || n;
  SELECT count(*) INTO n FROM silver.job_postings WHERE opening_status = 'Accepting applications';
  ASSERT n = 724, 'postings Accepting applications: ' || n;
  SELECT count(*) INTO n FROM silver.job_postings WHERE opening_status = 'Accepting applications' AND close_date >= DATE '2026-10-31';
  ASSERT n = 427, 'postings accepting and closing on or after 2026-10-31: ' || n;
  SELECT count(*) INTO n FROM silver.job_postings WHERE agency_level = 1;
  ASSERT n = 43, 'department-level postings: ' || n;
  SELECT count(*) INTO n FROM silver.agency_subelements;
  ASSERT n = 1072, 'agency_subelements rows: ' || n;
  SELECT count(*) INTO n FROM silver.occupational_series;
  ASSERT n = 822, 'occupational_series rows: ' || n;
  SELECT count(*) INTO n FROM synthetic.separations WHERE source_file = 'separations_202608_1.parquet' AND agency_subelement_code = 'HSBC';
  ASSERT n = 512, 'TSA rows in separations_202608_1: ' || n;

  -- synthetic (03-results, check cell 1)
  SELECT count(*) INTO n FROM synthetic.employment;   ASSERT n = 2725190, 'employment rows: ' || n;
  SELECT count(*) INTO n FROM synthetic.separations;  ASSERT n = 27799, 'separation rows: ' || n;
  SELECT count(*) INTO n FROM synthetic.accessions;   ASSERT n = 25852, 'accession rows: ' || n;
  SELECT count(*) FILTER (WHERE pay_redacted) AS redacted, count(*) FILTER (WHERE location_imputed) AS loc,
         count(*) FILTER (WHERE pay_imputed) AS pay,
         count(*) FILTER (WHERE (location_imputed OR pay_imputed) AND pay_redacted IS DISTINCT FROM true) AS leak
    INTO r FROM synthetic.employment WHERE snapshot_month = DATE '2026-08-01';
  ASSERT r.redacted = 171627, 'August 2026 pay_redacted: ' || r.redacted;
  ASSERT r.loc = 171296, 'August 2026 location_imputed: ' || r.loc;
  ASSERT r.pay = 162812, 'August 2026 pay_imputed: ' || r.pay;
  ASSERT r.leak = 0, 'imputed rows that are not redacted: ' || r.leak;

  -- geocoding (03-results): every August row with a usable state has a point; city precision >= 85%
  FOR r IN
    SELECT location_imputed, count(*) AS n_rows, count(*) FILTER (WHERE geo_precision IS NULL) AS no_point,
           round(count(*) FILTER (WHERE geo_precision = 'city')::numeric / count(*), 4) AS city_share
    FROM synthetic.employment
    WHERE snapshot_month = DATE '2026-08-01' AND duty_station_state NOT IN ('REDACTED', 'INVALID')
      AND NOT (duty_station_state = 'NO DATA REPORTED' AND duty_station_country_code <> 'US')
    GROUP BY location_imputed
  LOOP
    ASSERT r.no_point = 0, format('geocoding no_point for location_imputed=%s: %s', r.location_imputed, r.no_point);
    ASSERT r.city_share >= 0.85, format('geocoding city_share for location_imputed=%s: %s', r.location_imputed, r.city_share);
    IF NOT r.location_imputed THEN
      ASSERT r.n_rows = 53850, 'published August rows with a usable state: ' || r.n_rows;
    END IF;
  END LOOP;

  -- staffing plan (03-results, step 3)
  SELECT count(*) AS n_rows, count(DISTINCT agency_subelement_code || '|' || occupational_series_code) AS cells,
         count(*) FILTER (WHERE generation_rule LIKE 'Stress%') AS stress,
         sum(target_onboard) FILTER (WHERE fiscal_quarter = 'FY2027Q1') AS target, bool_and(is_synthetic) AS syn
    INTO r FROM synthetic.staffing_plan;
  ASSERT r.n_rows = 1680, 'plan rows: ' || r.n_rows;
  ASSERT r.cells = 210, 'plan cells: ' || r.cells;
  ASSERT r.stress = 6, 'stress rows: ' || r.stress;
  ASSERT r.target = 216516, 'FY2027Q1 target_onboard: ' || r.target;
  ASSERT r.syn, 'plan is_synthetic on every row';

  -- functions (03-results, acceptance outputs)
  SELECT * INTO r FROM semantic.separation_rate('2026-08-01', 'HSBC', '1802');
  ASSERT (r.headcount_start, r.headcount_end, r.separations_ttm, r.separations_ttm_excl_drp, r.quits, r.retirements, r.files_used)
         = (51605, 46913, 5922, 5913, 3731, 1114, 12), 'separation_rate TSA 1802 counts: ' || r::text;
  ASSERT (r.rate::numeric, r.rate_excl_drp::numeric) = (0.1202, 0.1200), 'separation_rate TSA 1802 rates: ' || r::text;
  SELECT * INTO r FROM semantic.separation_rate('2026-08-01', NULL, NULL);
  ASSERT (r.rate::numeric, r.rate_excl_drp::numeric) = (0.1203, 0.0989), 'separation_rate DHS rates: ' || r::text;
  SELECT * INTO r FROM semantic.plan_variance('FY2026Q1', 'HSBD', '1895');
  ASSERT (r.planned_hires, r.actual_accessions, r.variance, r.variance_pct::numeric, r.is_synthetic, r.cells, r.files_used)
         = (594, 475, -119, -0.2003, true, 1, 7), 'plan_variance CBP 1895 FY2026Q1: ' || r::text;
  SELECT count(*) INTO n FROM semantic.open_postings('2026-08-01', NULL, NULL);
  ASSERT n = 551, 'open_postings DHS 2026-08-01 rows: ' || n;
  SELECT * INTO r FROM semantic.attrition_ranking('2026-08-01', 100, 5) t WHERE t.rank = 1;
  ASSERT (r.agency_subelement_code, r.occupational_series_code, r.rate::numeric, r.rate_excl_drp::numeric)
         = ('HSCA', '0301', 0.5354, 0.3212), 'attrition_ranking rank 1: ' || r::text;
  SELECT count(*) INTO n FROM semantic.attrition_ranking('2026-08-01', 100, 5);
  ASSERT n = 5, 'attrition_ranking top_n rows: ' || n;
  FOR r IN SELECT * FROM semantic.imputation_quality() LOOP
    IF r.agency_subelement_code = 'HSCB' THEN
      ASSERT (r.rows_tested, r.rows_imputed) = (18743, 17987), 'imputation_quality FEMA counts: ' || r::text;
    ELSIF r.agency_subelement_code = 'HSCA' THEN
      ASSERT (r.rows_tested, r.rows_imputed) = (2161, 1970), 'imputation_quality CISA counts: ' || r::text;
    ELSE
      RAISE EXCEPTION 'imputation_quality unexpected component %', r.agency_subelement_code;
    END IF;
  END LOOP;
  SELECT count(*) INTO n FROM semantic.imputation_quality();
  ASSERT n = 2, 'imputation_quality rows: ' || n;
  RAISE NOTICE 'checks.pg.sql: all asserts passed';
END $$;

-- Draw-dependent, printed for the journal (Databricks gave 0.1174/0.6649 FEMA and 0.2817/0.7695 CISA;
-- TSA 1802 led with Alaska 3,053). Expect the same ballpark, not the same numbers.
SELECT * FROM semantic.imputation_quality();
SELECT * FROM semantic.headcount('2026-08-01', 'HSBC', '1802') LIMIT 5;

-- Determinism hash (03_semantic.sql L765-769): headcount and integer pay sum by component, series,
-- and (imputed) state for August 2026. Byte order (COLLATE "C") so the sort does not depend on the
-- database locale. Differs from the Databricks hash by design (md5 draw); must repeat across loads.
SELECT encode(sha256(convert_to(string_agg(s, ',' ORDER BY s COLLATE "C"), 'UTF8')), 'hex') AS august_2026_hash
FROM (SELECT concat_ws('|', agency_subelement_code, occupational_series_code, duty_station_state, n::text, pay::text) AS s
      FROM (SELECT agency_subelement_code, occupational_series_code, duty_station_state, count(*) AS n,
                   sum(round(annualized_adjusted_basic_pay)::bigint) AS pay  -- integer sum: order-independent
            FROM synthetic.employment WHERE snapshot_month = DATE '2026-08-01'
            GROUP BY agency_subelement_code, occupational_series_code, duty_station_state) g) h;

-- Role test, run as the agent (PGUSER=agent PGPASSWORD=$AGENT_PGPASSWORD): the first must fail with
-- "permission denied for schema synthetic", the second must return one row.
--   psql -c "SELECT count(*) FROM synthetic.employment"
--   psql -c "SELECT * FROM semantic.headcount('2026-08-01', 'HSBC', '1802') LIMIT 1"
