# Skill: what the records hold beyond the standard calculations

The standard calculations return only a few columns. The records behind them hold more, and a
one-off query can reach every field below. A field being absent from a standard calculation's
result never means the data lacks it.

Workforce snapshots (one row per employee per month), separations and accessions (one row per
action), all by component and occupational series:

- **Duty station city and state.** Present on every row, but for redacted rows (most TSA and CBP)
  the city and state are estimated from job postings, not published: label them estimated.
- **Grade and pay plan.** Every row has a pay plan (GS, SV for TSA bands, ES for the Senior
  Executive Service, and others) and a grade (ES rows carry grade 00).
- **Age bracket.** Five-year brackets (20-24 to 65 or more) on every row.
- **Length of service** in years, as a number on every row.
- **Annual basic pay.** Present on every row; estimated from job postings where OPM redacted it.
- **Supervisory status, tenure, work schedule.**
- **Separations:** effective month, separation category, and whether the separation came through
  the 2025 deferred resignation program. The categories, exactly: QUIT; RETIREMENT - VOLUNTARY,
  RETIREMENT - EARLY OUT, and RETIREMENT - OTHER (a question about retirements means all three);
  TERMINATION (EXPIRED APPT/OTHER); TRANSFER OUT - INDIVIDUAL TRANSFER and TRANSFER OUT - MASS
  TRANSFER; REDUCTION IN FORCE (RIF); OTHER SEPARATION.
- **Accessions:** effective month and accession category (new hire competitive or excepted,
  transfer in, SES).
- **Postings:** every listed series, minimum and maximum grade, open and close dates, openings
  (a number, or "Many"/"Few"), locations, hiring paths, clearance required.

What the records do not hold is in the data limits skill, and only there: names or person ids,
reasons for leaving, applicants, links from a posting to a hire, budget, and anything after
August 2026 (postings: after October 2026). If a question needs a field that is neither here nor
on that list, try a one-off query before saying it is not available.
