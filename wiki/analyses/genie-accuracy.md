# How often is Genie wrong, and is the agent's use of it defensible?

**Question (Ryan, 2026-10-31):** is the agent's use of Genie defensible? Do we know how often it is
wrong or fabricates facts?

**Answer in one line:** defensible by design, not yet by evidence. No published number transfers
to this space, so spec 05 measures Genie on its own question set and the result decides whether
the agent keeps it ([DECISIONS.md](../../DECISIONS.md), Genie measured).

## What is published

| Source | Figure | Caveat |
|---|---|---|
| Databricks, via a secondhand summary (2026-06) | 84.5% on an internal 28-question suite, against 52.4% and 25% for two unnamed coding agents ([Pebblous](https://blog.pebblous.ai/blog/databricks-genie-one-governed-data/en/)) | Run and graded by the vendor; the Databricks post itself was not read |
| Databricks research claim (2026-05) | 32% to "over 90%" against a coding-agent baseline on an internal benchmark ([aiweekly](https://aiweekly.co/alerts/databricks-genie-one-ships-sql-grounded-agentic-ai)) | Internal benchmark, relative claim |
| Agentic Fabriq, independent | 37.4% (exact match) and 53.1% (got the facts) on BIRD mini-dev; the lead over Snowflake Cortex Analyst is 7.2 points under one grading rule and 0.4 under the other ([Agentic Fabriq](https://www.agenticfabriq.com/blog/cortex-analyst-vs-genie-accuracy)) | The grading rule moves the result more than the product does |
| Databricks customer story | One space went from 54% to 100% on its own benchmark after tuning ([Databricks](https://www.databricks.com/blog/how-build-production-ready-genie-spaces-and-build-trust-along-way)) | Per-space and self-reported |
| Practitioner tutorial | 0% to 79% on 14 questions after adding business context ([Uthaman](https://shyamuthaman.com/databricks-genie-tutorial-business-context/)) | Small set |

Practitioner reports describe the failure that matters: a confident, plausible number from a
subtly wrong join or filter, on questions the demo never covered
([Apex Systems](https://www.apexsystems.com/insights/article/how-do-we-make-databricks-genie-reliable-enough);
[Lasak](https://dataengineerwiki.substack.com/p/build-a-production-grade-databricks)). Databricks
documents Genie as nondeterministic and ships benchmark tooling that scores answers against
reference SQL or results ([monitor](https://learn.microsoft.com/en-us/azure/databricks/genie-agents/monitor);
[benchmarks and review](https://www.databricks.com/blog/building-confidence-your-genie-space-benchmarks-and-ask-review)).

The honest range is 40% to 90% depending on data, configuration, and grading. None of it describes
a 65-column OPM table with imputed rows.

## Why the design is defensible anyway

1. **Genie never produces a graded number.** Every number the eval grades comes from a fixed-SQL
   function; Genie was rejected for that role because its SQL varies run to run
   ([DECISIONS.md](../../DECISIONS.md), Agent topology).
2. **The eight question families route to verified SQL.** The functions are Genie trusted assets.
   On 2026-10-31 the done-when question came back as a `headcount(...)` call, not generated SQL
   ([spec 03 results](../../challenge/specs/03-results.md)).
3. **Genie's numbers come from SQL that ran.** It does not narrate a number out of nothing; it
   runs a real query that may answer the wrong question. That error can be audited because the SQL
   comes back with the answer.
4. **Its reach is bounded.** It sees only the eight `semantic` views, never raw or unflagged rows.

## Where it is likely to be wrong on this data

Each returns a plausible, wrong number:

- counting separations by `reported_month` or `source_file` instead of `effective_month`;
- treating `pay_redacted IS NULL` as redacted (1,441 August rows are NULL, not redacted);
- stating imputed TSA or CBP locations as fact; imputed TSA screeners rank Alaska first
  ([spec 03 results](../../challenge/specs/03-results.md));
- using `staffing_plan` without saying it is synthetic;
- matching a series on `job_posting.series` (first listed) instead of
  `array_contains(occupational_series_codes, ...)`.

The six instruction lines in the space target the first four. Nobody has tested whether Genie
follows them.

## The measurement (spec 05)

- About 10 questions outside the eight function families, each with truth SQL, chosen to hit the
  traps above.
- Run each three times through the agent's Genie tool. Report Genie's pass^3 as its own row on the
  eval dashboard, separate from the graded functions.
- A run passes when the number is within tolerance of the truth and imputed or synthetic values
  are labeled. An unlabeled imputed or synthetic value fails the run whatever the number.
- The agent labels every Genie answer as exploratory and shows its SQL.
- Bar: Genie pass^3 of at least 70%. Below it, the agent loses the Genie tool and Genie stays a
  UI for human analysts. Either outcome is a defensible demo story: measured and kept, or
  measured and kept away from the agent.

## Not checked

The Databricks posts behind the 84.5% and 90% figures (search summaries only); whether Genie
reads view column comments when it writes SQL (it answered through a trusted function); Genie's
latency and cost per question under the service principal.
