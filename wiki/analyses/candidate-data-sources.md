# Candidate data sources for the Databricks build

**Question (Ryan, 2026-10-30):** Which data sources could we tie into Databricks that are relevant
to the workforce-risk briefing agent? Light Exa research, plus live probes of the APIs.

**Answer in one line:** two sources carry the whole demo, OPM's Federal Workforce Data (FWD) API
for supply and the USAJOBS Historic JOA API for demand, and they join on the same four-character
agency subelement code (verified: `HSBC` is the Transportation Security Administration in both).
One optional enrichment, OMB's budgeted FTE by agency, adds a plan-versus-actual story. Everything
else found is either governmentwide-only, embedded in a dashboard with no download, or needs a
crosswalk that costs more than it returns. Nothing on Databricks Marketplace or AWS Open Data
covers the federal workforce, so the path is direct API ingest into a Unity Catalog volume.

## Verified today by hitting the endpoints

These probes ran on 2026-10-30 from a laptop with `curl`; results are facts, not documentation.

| Check | Result |
|---|---|
| FWD list endpoint | `GET https://data.opm.gov/api/v1/files/separations?current=true` returns JSON metadata back to January 2005, no auth. Current 2026 employment files sit at versions 1 to 3, so versions do change ([API docs](https://data.opm.gov/get-data/api-access)). |
| FWD download size | The docs list a 400 error for "exceeded size byte limit of 25 MB". The August 2026 Employment Parquet downloaded through the API at 57.3 MB with 2,024,832 rows, so the limit does not apply to downloads. |
| Separations file | August 2026: 12,270 rows. Has `length_of_service_years`, `separation_category` (QUIT 5,536; RETIREMENT - VOLUNTARY 2,803; TERMINATION 1,854; TRANSFER OUT 848 + 16; RIF 74), `tenure` (RIF retention group), and `drp_indicator` for deferred-resignation separations. GAO's "57% of leavers had 11+ years" is reproducible from this file. |
| Column types | Every column in the Parquet files is a string, including `count`, `length_of_service_years`, and `annualized_adjusted_basic_pay`. The silver layer must cast. |
| Geography in the file | The dictionary and the file carry `duty_station_city`, `duty_station_county_code`, `locality_pay_area_code`, and `core_based_statistical_area_code`, so no external duty-station crosswalk is needed ([FWD Data Dictionary](https://data.opm.gov/FWD%20Data%20Dictionary.xlsx), dumped to `raw/2026-10-30-opm-fwd-data-dictionary.md`). |
| USAJOBS Historic JOA | `GET https://data.usajobs.gov/api/historicjoa?HiringDepartmentCodes=HS&StartPositionOpenDate=2026-10-01&EndPositionOpenDate=2026-10-02` returns rows with `hiringAgencyCode`, `jobcategories[].series`, `positionlocations[]`, and `totalOpenings`. No key, but Akamai returns 403 without a browser-style `User-Agent` header ([docs](https://developer.usajobs.gov/api-reference/get-api-historicjoa)). |
| The join key | USAJOBS `hiringAgencyCode` `HSBC` = Transportation Security Administration. OPM `agency_subelement_code` `HSBC` = Transportation Security Administration, 512 separations in August 2026. Same for `HSBD` (CBP), `TR93` (IRS), `VATA` (VHA). The USAJOBS agency subelement code list has 1,072 entries with `ParentCode`, which is the department. |
| `totalOpenings` | Returned `"many"` for a TSA screener posting. It is a string and often non-numeric, which confirms the announcements-are-not-vacancies caveat on the [impact page](user-problem-impact.md). |
| USAJOBS code lists | The docs give `/codelist/...`; the live path is `/api/codelist/...` ([docs](https://developer.usajobs.gov/api-reference/code-lists)). `agencysubelements` (1,072), `occupationalseries` (822, with `JobFamily`), and `missioncriticalcodes` (10) all return without a key. |
| Mission-critical code list | Not OPM's governmentwide MCO list. It is USAJOBS's own tag set: Cyber Security, Data Scientist, Economist, Privacy, Program/Project Management, Grants Management, STEM, Intelligence, plus two disabled. The MCO dimension must be hand-built from OPM's time-to-hire guidance (0201, 1102, 2210, and cyber series 0391, 0854, 0855, 1550) ([OPM T2H guidance](https://www.opm.gov/chcoc/transmittals/2024/T2H%20Data%20Call%20Memo%20and%20Guidance%209-12-2024%20rev_0.pdf)). |

## Tier 1: ingest in the build

| Source | What it gives | Access | Cadence | Role in the ontology layer |
|---|---|---|---|---|
| OPM FWD Employment | Month-end snapshot of every covered civilian employee, 2M+ rows, 64 columns incl. agency and subelement, occupation series, grade, pay plan, duty station down to county and CBSA, locality pay area, length of service, age bracket, supervisory status, appointment type, STEM flag, CFO Act flag | No auth, Parquet, list-then-download | Monthly; September 2026 data due 2026-11-04 ([data sources](https://data.opm.gov/resources/data-sources)) | `WorkforceSnapshot`; dimensions for Agency, SubAgency, Occupation, DutyStation derive from it |
| OPM FWD Separations | Personnel actions leaving federal service, same dimensions plus `separation_category`, `drp_indicator`, `personnel_action_effective_date_yyyymm` | Same | Monthly | `Separation` |
| OPM FWD Accessions | Entries, with `accession_category` (new hire vs transfer) | Same | Monthly | `Accession`; needed to say "net" anything |
| USAJOBS Historic JOA | Every announcement since 2017 with agency code, series, locations, grades, hiring paths, open and close dates, openings | No key; set `User-Agent`; continuation-token paging | Continuous | `JobPosting`; the demand side of the join |
| USAJOBS Search | Currently open announcements with richer fields | Free key from the developer portal | Live | Same object, "open now" view for the demo |
| USAJOBS code lists | Agency subelements with parent department, occupational series with job family | No key, `/api/codelist/...` | Static | Governed dimension tables with provenance |

The FWD data dictionary is the schema source for the whole Tier 1 layer. It lists 72 fields and
marks which appear in each of the three datasets; the August 2026 files carry 64 (Employment) and
69 (Separations) of them ([FWD Data Dictionary](https://data.opm.gov/FWD%20Data%20Dictionary.xlsx),
dumped to `raw/2026-10-30-opm-fwd-data-dictionary.md`).

A third-party mirror of USAJOBS exists: 3.26 million announcements from 2013 to 2026 as yearly
Parquet on Cloudflare R2, deduplicated across the Historic and Search APIs
([usajobs_historical](https://github.com/abigailhaddad/usajobs_historical)). Its counts show
announcements opened falling from 367,192 in 2024 to 168,533 in 2025. Use it only as a backfill
shortcut if paging the Historic JOA for years of history eats a day; anything the panel sees
should be recomputed from the official API and cited as such.

## Tier 2: one enrichment, if the core is green by day three

**OMB Historical Table 16.1, executive branch civilian FTE by agency, FY1981 to FY2027.** It is
the only public per-agency number that functions as a plan: the FY2026 and FY2027 columns are
budgeted FTE ([OMB historical tables](https://www.whitehouse.gov/omb/information-resources/budget/historical-tables/),
xlsx also mirrored by [FRASER](https://fraser.stlouisfed.org/title/383/item/721015)). Joining it
to FWD headcount lets the demo show plan-versus-actual at agency grain without any agency's
private Annual Staffing Plan. Two caveats to state: FTE is not headcount (the Employment file
includes part-time and non-pay-status employees), and OMB's agency groupings need a hand crosswalk
to OPM department codes for the two dozen agencies that matter. This mirrors the quarterly
variance explanation the [impact page](user-problem-impact.md) describes, which is why it is the
one enrichment worth the hours.

## Tier 3: looked at, not ingesting

| Source | Why not |
|---|---|
| OPM retirement claims monthly report ([PDF](https://www.opm.gov/retirement-center/retirement-statistics/retirement-processing-status.pdf)) | Governmentwide only, no agency grain; a PDF table. The story is good context (backlog fell from a record 65,237 in February 2026 to 8,814 in September 2026 per [FedSmith](https://www.fedsmith.com/2026/10/04/opm-retirement-backlog-falls-below-10k-in-september-2026/)), but it does not change an agency's decision. Quote it in the pitch if asked about the retirement wave; do not ingest. |
| BLS Current Employment Statistics, federal series `CES9091000001` ([BLS](https://data.bls.gov/timeseries/CES9091000001)) | Governmentwide monthly total, no agency grain. Useful only as a sanity check that FWD totals move the same direction (3,010k in January 2025 to 2,682k in September 2026). FRED serves it as CSV with no key. |
| OPM Time to Hire dashboard ([OPM](https://www.opm.gov/data/data-products/time-to-hire-dashboard/)) | Embedded Power BI, agency-submitted data via Connect.gov, no public download found. Borrow its vocabulary (80-day model, five intervals), not its data. |
| USAspending API, agency object class ([endpoints](https://api.usaspending.gov/docs/endpoints)) | Personnel compensation obligations by agency exist (`/api/v2/agency/<code>/object_class/`), but USAspending uses Treasury toptier codes, not OPM codes, and the crosswalk plus fiscal-year alignment is a day of work for a dollars-behind-headcount number the user did not ask for. |
| FEVS and successors | OPM cancelled the 2025 FEVS and on 2026-10-29 formally discontinued it, replacing it with agency-run Annual Employee Surveys with 10 core questions, results posted on agency websites within 90 days ([Federal News Network](https://federalnewsnetwork.com/workforce/2026/10/opm-formally-discontinues-federal-employee-viewpoint-survey/)). Last comparable public data is 2024. The Partnership for Public Service's own Public Service Viewpoint Survey (Nov to Dec 2025) has a dashboard by agency and subcomponent but no API and is not comparable to FEVS ([dashboard](https://bestplacestowork.org/data-dashboard/)). Engagement is out of scope for this build. |
| Legacy FedScope cubes and text files ([OPM datasets](https://www.opm.gov/data/datasets/)) | Superseded by FWD, which now reaches back to 2005 through the same API. Only reason to touch them is history before 2005. |
| Databricks Marketplace | Searched for federal workforce, OPM, USAJOBS, BLS, and Census listings. Nothing federal-workforce; Lightcast labor-market data is listed but paid with a trial ([Lightcast](https://lightcast.io/resources/blog/lightcast-brings-labor-market-intelligence-to-databricks-marketplace)). The panel answer: "I checked Marketplace; the data is not there, so the ingest job pulls the APIs into a Unity Catalog volume." |
| AWS Open Data Registry | Census ACS PUMS as RDF triples ([registry](https://registry.opendata.aws/census-dataworld-pums/)) and similar; nothing on the federal workforce. |
| EHRI Data Standards download ([data.opm.gov](https://data.opm.gov/data-standards/ehri-data-standards)) | The full code book for every EHRI element and value. Useful for comments on the Unity Catalog columns if time allows; not a dataset to load. |

## What this changes on other pages

- The [impact page](user-problem-impact.md) says "nothing joins separations to open postings."
  data.opm.gov states that FWD is "primarily" EHRI and that "other OPM data sources, including
  USAJOBS, are included as well" ([data sources](https://data.opm.gov/resources/data-sources)).
  Before repeating the claim to the panel, check what FWD exposes from USAJOBS; the join at
  sub-agency x series grain still appears to be ours.
- Two caveats added there: the Department of War coverage gap in June and July 2026 (June Status
  recovered 77,743 records, about 6,211 still missing, and the DD07 Dynamics feed absent both
  months, per OPM's release notes as summarized by
  [Federal Hiring Data](https://www.federalhiringdata.com/articles/opm-federal-workforce-data-api-guide-2026)),
  and the FEVS discontinuation.
- The `DECISIONS.md` data entry stands; the LOS field and the join key are now verified rather
  than assumed.

## Not verified

- Whether the Historic JOA's `hiringAgencyCode` is always populated at subelement grain, or
  sometimes only at department grain (the `agencyLevel` field suggests both occur).
- Rate limits on the FWD API (a 429 is documented, no numbers given) and on Historic JOA paging.
- Whether FWD's USAJOBS-derived content overlaps the demand-side join.
- OMB Table 16.1 agency groupings against OPM department codes; the crosswalk is day-one work if
  Tier 2 proceeds.
