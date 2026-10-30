# Wiki log

Append-only. Entry format: `## [YYYY-MM-DD] <op> | <title>`.
Recent entries: `grep "^## \[" wiki/log.md | tail -5`

## [2026-10-30] setup | Wiki scaffolded

Created the schema (AGENTS.md), index, and log. No sources yet.

## [2026-10-30] query | Build challenge problem selection

Researched with Exa whether federal workforce planning is the right build-challenge problem. Found
the workforce posting is a Palantir role, found the FDE program's Databricks posting, OPM's new
open Federal Workforce Data API, and GAO's 2025 workforce numbers. Wrote
`analyses/build-challenge-problem-selection.md`. Saved four name-bearing sources to `raw/`.

## [2026-10-30] ingest | Build challenge email (source one)

Wrote `sources/build-challenge-email.md`, `entities/firm-federal-fde-program.md`,
`concepts/build-challenge.md`, `concepts/multi-agent-orchestration.md`, and created
`synthesis.md`. Updated the analysis for Ryan's platform decision: Databricks on AWS, paid, under
$50, torn down after the interview.

## [2026-10-30] query | FDE build challenge playbook

Exa research on how FDE take-home build challenges are evaluated and how to do well. Wrote
`analyses/fde-build-challenge-playbook.md` and `concepts/agent-evaluation.md`; added thesis point 5
to `synthesis.md`. Firm-specific candidate reports were thin; saved them to `raw/`.

## [2026-10-30] setup | Decision log started

Created `DECISIONS.md` at the repo root with five seeded decisions (problem, platform, data, LLM
access, evaluation) and six pending ones. Added it to the layout in `AGENTS.md`.

## [2026-10-30] decision | Claude via Anthropic API, Databricks as MCP tool layer

Ryan's read that the Firm's clients run agents in Palantir AIP above Databricks is supported by the
2025 Palantir-Databricks partnership. `DECISIONS.md` entry four rewritten; the problem-selection
analysis table updated to match. Researched Palantir AIP Developer Tier as a possible agent layer.

## [2026-10-30] decision | Strands on AgentCore, ontology-like layer in Unity Catalog

Ryan chose AWS Databricks + Claude API + Strands Agents on Bedrock AgentCore, with an
ontology-like semantic layer in Unity Catalog instead of Palantir DevTier. Two entries added to
`DECISIONS.md`; analysis table and orchestration concept page updated.

## [2026-10-30] query | Build cost estimate

Priced every component of the plan on AWS us-east-1 list rates, plus AgentCore. Finding: the
Databricks trial's $400 credit covers the week; the risks are a running SQL warehouse and Lakebase
defaults. Wrote `analyses/build-cost-estimate.md`; added a cost line to the platform decision.

## [2026-10-30] query | User, problem, and impact research

Exa deep research on the federal workforce-planning analyst persona. Wrote
`analyses/user-problem-impact.md` with the mandate trail (5 CFR 250, HRStat, MCO staffing charts,
Merit Hiring Plan, 2025 annual personnel plans), HR capacity loss numbers, and three-sentence
answers to the challenge prompt.

## [2026-10-30] decision | User and problem statement

Folded the Exa deep-research run into `analyses/user-problem-impact.md`: the 2026-10-29 OPM final
rule and Annual Staffing Plan cycle (verified from the Federal Register API and three OPM memo
PDFs), FWD Chat as the incumbent to differentiate from, HUD OIG peer benchmarking precedent, and
data caveats. Logged the user and problem statement in `DECISIONS.md`; synthesis point 6 added.
