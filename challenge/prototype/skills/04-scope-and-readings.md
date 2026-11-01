# Skill: the open cell, and reading a question

The review screen is open on one cell: **CBP Officers (component HSBD, series 1895), FY2026 Q1
(October to December 2025)**. A question that names no component, occupation, or period is about
that cell; "this quarter" is FY2026 Q1; "these officers" are CBP Officers. A question that names
another cell (TSA screeners, FEMA, all of DHS) is about what it names. Postings questions with no
date use 2026-08-01, the date the brief reports.

Answer the most plausible reading; never ask which reading was meant (rule 6). When the question
left something open, the last sentence of the prose states the reading taken and the nearest
alternative.

## Worked example: "How does this compare with Q2?"

Reading: the open cell's plan variance, FY2026 Q2 (January to March 2026) against FY2026 Q1.
Calls: `plan_variance` with `FY2026Q2`, `HSBD`, `1895`, and with `FY2026Q1` if Q1 is not already
in this conversation (a two-period comparison may use two calls).
Answer shape (numbers come from the results, never from here):

    Verified
    CBP Officers landed <A2> accessions against a plan of <P2> in FY2026 Q2 (January to
    March 2026), a variance of <V2> (<pct2>), against <V1> (<pct1>) in FY2026 Q1 (October to
    December 2025). Later OPM files add accessions, so both gaps can
    narrow. I read this as the plan variance for CBP Officers in Q2 against Q1; if you meant
    another measure, such as separations, say so.

`answer_value` is the Q2 variance.

## Worked example: "What was advertised in Texas?"

Reading: postings open on 2026-08-01 against the open cell, kept to those whose `states` include
Texas.
Call: `open_postings` with `2026-08-01`, `HSBD`, `1895`. Then keep the rows whose `states` list
contains "Texas", and count the rows whose `states` is empty or `[null]` (no state given).
Answer shape:

    Verified
    On August 1, 2026, <n> of the <total> CBP Officer announcements open listed Texas: <title,
    grade, openings for each>. <m> announcements give no state, so Texas may have more. Open on a
    past date is an upper bound, since postings filled or cancelled early are invisible. I read
    this as CBP Officer postings open on August 1, 2026; if you meant all CBP occupations or
    another date, say so.

`answer_value` is <n>, the count of announcements listing Texas.

## Worked example: a period when hiring could not happen

The analyst supplies: "No one could be onboarded from October 1 to November 12, 2025."
Method: prorate the plan, never the actuals. The actual accessions already reflect what happened,
so never subtract anything from them. Fetch `plan_variance` for the open cell and quarter if it
is not already in this conversation, then scale the planned hires to the days hiring was
possible and compare the unchanged actuals against that scaled plan.
Answer shape (numbers come from the results, never from here):

    Verified
    Assuming, as you state, that no one could be onboarded from October 1 to November 12, 2025,
    the plan scaled to the days hiring was possible is about <P'> hires, and the <A>
    actual accessions land <V'> (<pct'>) against it, compared with <V> (<pct>) against the full
    plan of <P>.
    - Days in the quarter: October 1 to December 31, 2025 = 31 + 30 + 31 = 92
    - Days hiring could not happen: October 1 to November 12 = 31 + 12 = 43
    - Days hiring was possible: 92 - 43 = 49
    - Scaled plan: <P> x 49 / 92 = <P'>
    - Variance against the scaled plan: <A> - <P'> = <V'>, or <V'> / <P'> = <pct'>
    Later OPM files can add accessions. Accessions by month for
    October to December 2025 are the better test of the assumption; a one-off query can give them.

Do not claim the assumption "explains" the shortfall; state what the comparison shows.
`answer_value` is the variance against the scaled plan.
