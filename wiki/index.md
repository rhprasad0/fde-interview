# Wiki index

Every wiki page, with a one-line summary. The agent updates this on every ingest
and reads it first on every query.

## Synthesis

- [Synthesis](synthesis.md): the thesis (panel is buying an FDE; Databricks on AWS; federal workforce planning; expect a Palantir-literate panel) and open research questions.

## Sources

- [Build challenge email](sources/build-challenge-email.md): the 2026-10-29 email issuing the one-week agentic build challenge, its complexity examples, interview format, and 2026-11-05 deadline.

## Entities

- [The Firm's federal FDE program](entities/firm-federal-fde-program.md): the center of excellence running Ryan's interview, its partner platforms, open FDE roles, and the federal arm's Databricks footprint.

## Concepts

- [Build challenge](concepts/build-challenge.md): format, requirements, Ryan's added constraints, and the decision.
- [Multi-agent orchestration](concepts/multi-agent-orchestration.md): when splitting into supervisor and workers is justified, and how Databricks supports it.
- [Agent evaluation](concepts/agent-evaluation.md): why "how do you know it works" decides FDE deep dives, and the minimal MLflow eval set for a one-week build.

## Analyses

- [Build challenge: is federal workforce planning the right problem?](analyses/build-challenge-problem-selection.md): scores workforce planning against spending, cyber, and supply-chain alternatives on the challenge rubric; recommends a federal workforce-risk briefing agent on Databricks on AWS fed by OPM's open API.
- [How to perform well on an FDE build challenge](analyses/fde-build-challenge-playbook.md): what evaluators reward across FDE take-home loops, failure modes, a 15-minute demo structure, a deep-dive question bank, federal impact framing, and a build-week checklist.
- [Who the user is, why this problem, what impact](analyses/user-problem-impact.md): the workforce-planning analyst persona, the 2025-2026 OPM mandates and HR capacity loss that make the problem acute, impact in three levels, and three-sentence answers to the challenge prompt.
- [Build cost estimate](analyses/build-cost-estimate.md): Databricks and AWS line items for the one-week build, trial credits, the two ways to overspend, budget alerts, and a teardown checklist.
- [Databricks in mission environments](analyses/databricks-in-mission-environments.md): what is inside the FedRAMP High and IL5 boundary on AWS GovCloud (managed MCP yes, Unity Gateway MCPs, Supervisor Agent, AI Functions, Lakebase no), the AWS-plus-Databricks public-sector gateway pattern, and what it changes for the MCP-path decision.
- [Pre-spec gaps](analyses/pre-spec-gaps.md): Unity Catalog functions cannot write, resolved by making the agent read-only; CloudWatch as the audit record; a plain eval harness to Delta with MLflow as a stretch; what is verified; the day-one checklist; two questions only Ryan can answer.
- [Observability and governance minimum](analyses/observability-governance-minimum.md): the four dashboard panels, provenance on every number, five governance artifacts, and an M-25-21 determination to show on demo day; which Databricks surfaces apply to the workspace MCP path; what is logged but not shown and what is skipped.
- [Candidate data sources](analyses/candidate-data-sources.md): live-probed OPM FWD and USAJOBS APIs (schema, join key, size limit), the one enrichment worth adding (OMB budgeted FTE), and the sources looked at and skipped with reasons.
- [OPM redaction and imputation](analyses/opm-redaction-and-imputation.md): OPM masks location, pay, and bargaining unit on 76% of DHS records, by occupation (all screeners, CBP officers, Border Patrol); why donor imputation fails; USAJOBS postings as the source for synthetic location and pay; requirements and open questions for spec 03.
