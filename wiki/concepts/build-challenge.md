# Build challenge

The take-home round of the Firm's federal FDE hiring process: build an agentic system in one week,
then demo and defend it. Source: [build challenge email](../sources/build-challenge-email.md).

## Format

| Segment | Minutes | Content |
|---|---|---|
| Presentation | 15 | Problem choice, users, expected impact, technical choices, architecture, LLM usage. Mostly live demo, code walkthrough, architecture review. Optional slides for the problem statement only. |
| Deep dive | 30 | Interviewer questions on the demo. |
| Standard | 15 | Technical and behavioral questions; no prep required. |

## Requirements

- Built on Claude, Gemini, or GPT.
- Not production-ready, but complex enough to show skill. Named examples: multi-agent
  orchestration, an MCP server and/or client, API data access, skills.
- One week from receipt. Issued 2026-10-29; due EOD 2026-11-05.

## Ryan's added constraints

- Databricks must be load-bearing (the round-one question was whether Ryan can pick up Databricks
  fast).
- Deployed on real infrastructure: Databricks on AWS, under $50 for the week, torn down afterward.
- The public repo must not name the Firm (see `AGENTS.md`).

## Decision

Federal workforce-risk briefing agent; see
[problem selection analysis](../analyses/build-challenge-problem-selection.md) for the rubric,
alternatives, architecture, and risks.

## Related

- [The Firm's federal FDE program](../entities/firm-federal-fde-program.md)
- [Multi-agent orchestration](../concepts/multi-agent-orchestration.md)
