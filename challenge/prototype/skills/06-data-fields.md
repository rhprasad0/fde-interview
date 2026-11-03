# Skill: what the records hold beyond the standard calculations

The standard calculations return only a few columns. The records behind them hold more, and a
one-off query can reach every field below. A field being absent from a standard calculation's
result never means the data lacks it.

A one-off query is one Postgres SELECT against the views in schema `semantic` (the only schema you
can read; write the bare view name): `workforce_snapshot` (one row per employee per month,
`snapshot_month`), `separation` and `accession` (one row per action, `effective_month`),
`job_posting`, `staffing_plan`, `imputation_quality`, `component`, `occupation`. Every workforce
row carries `agency_subelement_code`, `agency_subelement`, `occupational_series_code`,
`occupational_series`, and `source_file`. Months are dates on the first of the month.

Workforce snapshots, separations and accessions, all by component and occupational series:

- **Duty station city and state** (`duty_station_city`, `duty_station_state`). Present on every
  row, but for redacted rows (most TSA and CBP) the city and state are estimated from job
  postings, not published (`location_imputed` is true): label them estimated.
- **Grade and pay plan** (`grade`, `pay_plan_code`). Every row has a pay plan (GS, SV for TSA
  bands, ES for the Senior Executive Service, and others) and a grade as zero-padded text ("09";
  ES rows carry "00"; TSA bands are letters).
- **Age bracket** (`age_bracket`). Five-year brackets as text ("20-24" to "65 or more") on every row.
- **Length of service** (`length_of_service_years`) in years, as a number on every row.
- **Retirement eligibility** comes from age and service together. CBP Officers (1895), Border
  Patrol agents (1896), and other law-enforcement series have enhanced coverage: eligible at age
  50 with 20 years of service, or at any age with 25. Regular FERS staff: age 62 with 5 years, 60
  with 20, or the minimum retirement age (57) with 30. For eligibility n years out, add n to both
  age and service. Age is a bracket, so count each bracket from its lower bound (the youngest
  anyone in it can be) and call the result an approximation.
- **Annual basic pay** (`annualized_adjusted_basic_pay`). Present on every row; estimated from job
  postings where OPM redacted it (`pay_imputed` is true).
- **Supervisory status, tenure, work schedule** (`supervisory_status`, `tenure`, `work_schedule`).
- **Separations:** `effective_month`, `separation_category`, and `drp_indicator` ('Y' when the
  separation came through the 2025 deferred resignation program). The categories, exactly: QUIT;
  RETIREMENT - VOLUNTARY, RETIREMENT - EARLY OUT, and RETIREMENT - OTHER (a question about
  retirements means all three, `LIKE 'RETIREMENT%'`); TERMINATION (EXPIRED APPT/OTHER); TRANSFER
  OUT - INDIVIDUAL TRANSFER and TRANSFER OUT - MASS TRANSFER; REDUCTION IN FORCE (RIF); OTHER
  SEPARATION.
- **Accessions:** `effective_month` and `accession_category` (new hire competitive or excepted,
  transfer in, SES).
- **Postings** (`job_posting`): the posting agency's `agency_subelement_code` and
  `agency_subelement` (a series question about one component filters on it), `control_number`,
  `position_title`, every listed series
  (`occupational_series_codes`, a JSON array: match one with `occupational_series_codes ? '1895'`;
  `series` is the first listed), `minimum_grade` and `maximum_grade` (text), `open_date` and
  `close_date`, `total_openings` (a number, NULL when the posting says "Many" or "Few", which
  `total_openings_raw` keeps), `locations` (a JSON array of objects with `positionLocationCity`
  and `positionLocationState`), `hiring_paths`, `security_clearance`.
- **Plan** (`staffing_plan`): `fiscal_quarter` ("FY2026Q1"), `quarter_start`, `planned_hires`,
  per component and series.

What the records do not hold is in the data limits skill, and only there: names or person ids,
reasons for leaving, applicants, links from a posting to a hire, budget, and anything after
August 2026 (postings: after October 2026). If a question needs a field that is neither here nor
on that list, try a one-off query before saying it is not available.
