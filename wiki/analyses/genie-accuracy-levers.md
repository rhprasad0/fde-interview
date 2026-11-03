# Raising Genie's accuracy: the levers, and what our space is missing

**Question (Ryan, 2026-11-02):** after the agent hill climb, how do we improve Genie's own scores?

**Answer in one line:** our Genie space has none of the configuration Databricks says drives
accuracy. It runs on table and column comments alone, with no column values visible, no named
definitions, no example SQL, and no benchmarks. The fix order is values, definitions, examples,
with benchmarks to measure each step.

## What the live space has (checked 2026-11-02)

The space was created from `challenge/genie/dhs-workforce.json` through the API. Its live export
shows eight tables with **no column configuration** (no format assistance, no entity matching), **no
example SQL queries**, **no SQL expressions** (measures, filters, fields), **no join specs**, **no
benchmarks**, one block of six text instructions, and the eight trusted functions. A community
reference for the space format says API-created spaces default to format assistance off
([schema reference](https://github.com/sean-zhang-dbx/prompt-to-genie/blob/main/references/schema.md));
the Databricks docs do not say so directly.

## What Databricks says drives accuracy, in order

1. **Well-described data.** Table and column descriptions, ambiguous columns removed, and visible
   values: format assistance gives representative values, and entity matching gives the distinct
   values of up to 120 string columns so a filter matches the data ("Florida" becomes `'FL'`)
   ([tune quality](https://docs.databricks.com/aws/en/genie-agents/tune-quality);
   [troubleshooting](https://docs.databricks.com/aws/en/genie-agents/troubleshooting)).
2. **SQL expressions:** named measures, filters, and fields with synonyms; "Genie applies the logic
   exactly as written rather than interpreting it from natural language"
   ([tune quality](https://docs.databricks.com/aws/en/genie-agents/tune-quality)).
3. **Example SQL queries** for complex or ambiguous patterns, titled with the typical user
   phrasing; "aim for at least five"
   ([best practices](https://docs.databricks.com/aws/en/genie-agents/best-practices);
   [Genie API](https://docs.databricks.com/aws/en/genie-agents/conversation-api)).
4. **Text instructions last, and few.** Too many reduce accuracy
   ([best practices](https://docs.databricks.com/aws/en/genie-agents/best-practices);
   [Solomon](https://www.databricks.com/blog/data-dialogue-best-practices-guide-building-high-performing-genie-spaces)).
5. **Benchmarks** to measure every change: questions with a SQL answer, run as fresh conversations,
   graded by comparing result sets. Benchmarks are never used as context
   ([monitor](https://docs.databricks.com/aws/en/genie-agents/monitor)). A Beta API starts runs and
   returns per-question assessments
   ([eval runs](https://docs.databricks.com/api/workspace/genie/geniecreateevalrun)).

Published climbs follow that order: Databricks' own team from about 50% to over 95% (clean tables,
then metric views, then nightly regression runs)
([talk](https://answers.databricks.com/supercharging-genie-performance-metric-views-6rEl8md1kT8));
a marketing space 54% to 77% to 100% (metadata, metric definitions, instructions)
([Databricks](https://www.databricks.com/blog/how-build-production-ready-genie-spaces-and-build-trust-along-way));
a supply-chain space 53% to 100%
([Syren](https://syrencloud.com/guide-on-how-to-build-high-accuracy-databricks-genie-spaces/)).
All are self-reported on small suites.

## Our Genie failures, mapped to the levers

| Seen in the eval | Cause | Lever |
|---|---|---|
| C14 retirements filtered to two of three categories | Genie cannot see the values it filters on | entity matching on `separation_category`; a "retirement" filter expression |
| C16 counted 322 "senior executives" (truth 44) | no definition of SES | filter expression `pay_plan_code = 'ES'` with synonyms |
| C10, C07 wrong month (December 2025; `reported_month`) | ambiguous date columns | a "month" field expression on `effective_month`; column descriptions; an example query |
| C15 varying length-of-service filters | no canonical measure | measures for separations and separation rate |
| C12 listed 500 rows instead of counting | pattern | an example query: count postings by series with `array_contains` |

## Recommended order

1. Benchmarks first, so each change is measured: Genie asked directly, beside Genie through the
   agent, which separates "Genie answered wrong" from "the agent asked badly".
2. Format assistance and entity matching on the categorical columns (a `column_configs` edit).
3. About eight SQL expressions for the review's standard definitions.
4. Five to eight example SQL queries for patterns, written fresh.

Expressions and examples state general definitions and patterns, never the eval's questions or
answers; copying eval questions in as examples would teach to the test. Benchmarks are the safe
place for eval questions because Genie does not learn from them.

**Not now:** metric views (GA April 2026,
[Databricks](https://www.databricks.com/blog/redefining-semantics-data-layer-future-bi-and-ai)),
the largest documented gain but semantic-layer work deferred with the other data engineering;
Genie One MCP and Agent mode, which replace the tool rather than tune it
([Genie One MCP](https://docs.databricks.com/aws/en/agents/mcp-tools/genie-mcp)).

## Benchmarks built (2026-11-02)

The eleven Genie-tier eval rows with truth SQL are now benchmarks in the space
(`challenge/scripts/genie_bench.py`). Genie answering them directly passes 8 of 22 over two runs
(5/11 and 3/11), against 83% for the same questions through the agent. Genie's own benchmark grader
scores only 3 of 22: it fails correct answers on result format, so the script also grades Genie's
rows with the agent eval's scorers. Details and the errors seen: `challenge/eval/journal.md`,
"Genie direct".

## Not checked

Whether every lever applies equally through the per-space MCP endpoint the agent uses (the docs
describe the space configuration as applying to every path into it); availability of entity
matching in GovCloud.
