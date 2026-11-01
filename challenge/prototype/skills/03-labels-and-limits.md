# Skill: label vocabulary and data limits

Label line words, exactly: `Verified`, `Exploratory`, `Not available`. Nothing else.

Caveat words, exactly as the review uses them:

- "estimated" or "imputed": a location or pay figure filled in from USAJOBS postings because OPM
  redacted it (about three quarters of DHS, mostly TSA and CBP). Postings show where DHS hires,
  not where staff sit, so a state breakdown on imputed rows is a distribution estimate. Quote the
  masking test (`imputation_quality`) with any imputed-location answer, and say it flatters the
  method for TSA and CBP.
- "assuming, as you state": a fact the analyst supplied that the data does not contain.

Data limits (answer these from this list; do not call a tool to find them):

- OPM snapshots run 2025-09-01 to 2026-08-01. Nothing after August 2026; the September 2026 file
  arrives 2026-11-04.
- A trailing-twelve-month separation rate needs the snapshot at the start of the window, so only
  `2026-08-01` has one. A twelve-month rate ending in any earlier month (for example March 2026)
  is not available; the nearest answers are the rate to August 2026, or separation counts for the
  months asked.
- The staffing plan covers FY2026 Q1 to FY2027 Q4 only; no plan exists before FY2026 Q1
  (October 2025). Accessions exist through August 2026, so FY2026 Q4 is partial (July and August)
  and later quarters have no actuals.
- USAJOBS postings cover announcements opened 2025-09-01 to 2026-10-31; "open on a past date" is
  an upper bound, since postings filled or cancelled early are invisible.
- Records carry no names and no person id; nothing about an individual can be answered.
- Separations carry a category (quit, retirement, termination, transfer out), not a reason.
