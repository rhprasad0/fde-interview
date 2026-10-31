# OPM redaction in the DHS data, and how to impute it

Measured 2026-10-31 on the spec 02 silver tables ([results](../../challenge/specs/02-results.md)).
Decided the same day: impute location and pay into a separate `synthetic` schema, specified
in spec 03 (`DECISIONS.md`, 2026-10-31, Imputation).

## What is redacted

OPM publishes the literal `REDACTED` in place of the value. On every row where it appears, three
column groups are masked together, and nothing else is:

| Group | Columns | Share of DHS rows |
|---|---|---|
| Location | 19: `duty_station_*` (code, city, county, state, country), `core_based_statistical_area*`, `consolidated_statistical_area*`, `locality_pay_area*` | employment 75% (all 12 snapshots), separations 61%, accessions 91% |
| Pay | `annualized_adjusted_basic_pay` (silver keeps `pay_redacted`) | the same rows as location |
| Bargaining unit | `bargaining_unit*`, `personnel_office_identifier_code` | the location rows, plus all of CBP, ICE, and Secret Service |

In the August 2026 employment snapshot, 171,627 of 225,574 DHS records (76%) have pay redacted.
All 171,627 also have location redacted, and no row has location redacted without bargaining unit.

**Not redacted:** component (`agency_subelement_code`), occupational series, pay plan, grade,
step or rate type, tenure, age bracket, education, supervisory status, work schedule, length of
service, and appointment type. Headcount, attrition, and grade-mix questions therefore work on
published data. The redaction removes three things: where people work, what they are paid, and
their union status. Location is one of the four slices in the problem statement
(`DECISIONS.md`, Problem: sub-agency x occupation x location x tenure).

## The redaction follows the occupation

Share of August 2026 records with location redacted, by component:

| Component | Records | Redacted |
|---|---|---|
| CBP (`HSBD`) | 70,843 | 95% |
| ICE (`HSBB`) | 28,674 | 93% |
| TSA (`HSBC`) | 59,342 | 91% |
| Secret Service (`HSAD`) | 8,694 | 85% |
| USCIS (`HSAB`) | 20,327 | 67% |
| FLETC (`HSBE`) | 1,424 | 59% |
| DHS HQ (`HSAA`) | 4,144 | 31% |
| Coast Guard civilians (`HSAC`) | 8,664 | 7% |
| FEMA (`HSCB`) | 20,208 | 0.6% |
| CISA (`HSCA`) | 2,204 | 1.6% |

FEMA's 20,208 records include 1,338 whose pay is NULL (missing, not `REDACTED`) with location
published, and CISA's 8; spec 03's masking test uses the 18,743 and 2,161 with `pay_redacted = false`.

By series, every record in 1802 (51,306, mostly TSA screeners), 1801 (33,498), 1895 (CBP officers,
27,650), 1896 (Border Patrol, 22,464), 1811 (criminal investigators, 13,650), 0401, 0083, and
0132 is redacted. Some series are redacted in part: 0301 has 2,823 of 9,354 redacted, 0905 2,456
of 4,058, and 0343 974 of 8,645. Within TSA, 1802 is 100% redacted, and 0343, 0086, 0301, and 0201
are 0%.

## What this rules out, and what can be used instead

- **Ruled out: borrowing values from similar unredacted records.** The largest series have no
  unredacted records at all, so the nearest donors would be office staff in the same component,
  and screeners would be placed in headquarters buildings with analysts' pay.
- **Ruled out: computing pay from the GS table alone.** Pay for TSA's 53,698 redacted records is on
  TSA's own `SV` bands, which have no steps. CBP and ICE redacted records are mostly `GS`, with 5,184
  and 6,570 `GL` (law enforcement special rates). Even for GS, locality pay needs the locality pay
  area, which is itself redacted.
- **Usable: the USAJOBS postings already in silver.** `silver.job_postings` holds 1,155 TSA
  postings in series 1802 and 469 CBP postings in 1895. Each carries `locations` and
  `minimum_salary`/`maximum_salary`, and both are published for exactly the occupations OPM
  redacts.
  - Location: draw from the posting locations for the same component and series.
  - Pay: draw within the posted salary range for the same component, series, and grade.
  - Fallback, for the partly redacted series: unredacted records in the same component, series,
    and grade.
  - **Caveat:** postings show where DHS is hiring, not where the current workforce sits; airports
    with high turnover will be over-represented.

## Requirements for the imputed tables

- `silver` stays untouched as the record of what OPM published.
- The imputed copies of `employment`, `separations`, and `accessions` live in a new `synthetic`
  schema (a Terraform change in `challenge/infra/main.tf`). The service principal needs no new
  grant: it reads through `semantic` functions, which run with the owner's rights.
- Every row carries `location_imputed` and `pay_imputed`; the published `pay_redacted` stays.
- Table comments, the semantic functions, and the agent's instructions say the values are
  synthetic. An answer that rests on an imputed column must say so.
- Bargaining unit stays as published.

## Settled in spec 03 (2026-10-31)

Measured on the silver tables the same day; the method is in
[spec 03](../../challenge/specs/03-semantic-layer.md), step 2.

- **Reproducibility.** A hash of the row's columns alone is not enough: 45,106 of the 225,574
  August 2026 records have an identical twin (largest group 44), and identical rows would all
  draw the same airport. The draw hashes the row plus its position among identical rows; since
  identical rows are indistinguishable, the result is the same multiset on every run.
- **Consistency across months.** Independent per snapshot, accepted. Counts by location are
  distribution-level and no question follows an individual.
- **Pool filters.** Of 28,261 posting-locations, 1,047 have no state ("Location Negotiable After
  Selection") and 306 are foreign; both are dropped. 1,025 postings carry a placeholder minimum
  salary (as low as 1.0) and are excluded from the pay pool only. 331 redacted rows (0.2%) have
  no US posting location in their component and series, and 8,815 (5.1%) no posting at their pay
  plan and grade; they stay `REDACTED` or NULL and flagged false. Grades need zero-padding on the
  USAJOBS side (`9` versus OPM `09`); TSA `SV` bands are letters on both sides.
- **The check.** FEMA (18,743 unredacted rows, 931 postings) and CISA (2,161, 119) are masked
  and imputed with the same method; the result is stored in `synthetic.imputation_quality` and
  disclosed by the agent. Ryan withdrew the 0.5 pass bar the same day ("more art than science");
  the number informs, it does not gate.
- **Points for a map.** Every row with a city gets the Census Gazetteer 2025 place point
  (`geo_precision = 'city'`, about 88% of rows on an exact name match) or the state centroid
  (`'state'`); Puerto Rico needs a heuristic because OPM reports it as `NO DATA REPORTED`.
- **Only three columns are imputed** (city, state, abbreviation) plus pay; the other sixteen
  location columns stay `REDACTED`.
