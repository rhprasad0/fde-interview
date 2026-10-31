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

## Open for spec 03

- **Reproducibility.** OPM rows carry no id, so a rerun must not reshuffle the imputed values.
  Seed the draw from a hash of the row's own columns plus its source file, not from `rand()`.
- **Consistency across months.** The same person appears in twelve snapshots with no id to link
  them. Independent draws will move a screener between airports every month. Decide whether that is
  acceptable for counts by location, or whether to impute once per stable attribute combination.
- **Postings without a usable location** ("Multiple locations", or no posting for a series and
  component): fall back to the component's unredacted distribution, or leave the value `REDACTED`
  and flag it.
- **How to check it.** The DHS components with little redaction (FEMA, CISA) can be masked on
  purpose and imputed with the same method, to see how far the draw lands from the truth.
