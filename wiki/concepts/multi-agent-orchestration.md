# Multi-agent orchestration

Splitting an agentic system into several LLM-driven workers coordinated by a supervisor, where
each worker owns a distinct tool set or data source. Named by the
[build challenge email](../sources/build-challenge-email.md) as one example of "sufficient
complexity."

## When the split is justified

A multi-agent design earns its place when workers differ in tools, data, or permissions, not when
one prompt is cut into pieces for show. The build first proposed four workers, then applied the
test and rejected the split (`DECISIONS.md`, 2026-10-30):

| Proposed worker | Tools and data | Why it failed the test |
|---|---|---|
| Ingest / data-quality checker | OPM and USAJOBS APIs, Unity Catalog volume, Delta tables | Has no decision to make; a data-quality step in the Lakeflow job does it deterministically |
| Workforce analyst | UC functions and Genie via MCP | Same Unity Catalog layer and same service principal as the next row |
| Hiring-market analyst | USAJOBS views via the same MCP endpoints | One more tool on the same trust boundary, not a different one |
| Briefing writer | Skills for format and OPM code lists | A prompt section, not a permission boundary |

The reliability target decided it. pass^3 of 80% needs roughly 93% per run, and every handoff
between agents is another place a run can fail. The chosen build is one agent with governed
tools; orchestration is a Lakeflow job, which is the kind a federal panel recognizes. A second
agent is added only if a tool needs a different trust boundary, for example one that writes.

## Chosen harness

Strands Agents (Python) with the OpenAI model provider, deployed to Amazon Bedrock AgentCore
Runtime, consuming Databricks managed MCP servers as tools through AgentCore Gateway
(`DECISIONS.md`, 2026-10-30). Strands
has native MCP client support and a documented AgentCore deployment path
([Strands docs](https://strandsagents.com/docs/user-guide/sdk/deploy/deploy_to_bedrock_agentcore/)).
The Databricks-hosted options below were considered and set aside so the agent stays a separable
layer above the lakehouse.

## On Databricks (not chosen)

Databricks ships a managed Supervisor Agent (GA since 2026-04) that orchestrates multiple agents
and tools, supports custom MCP servers and custom agents hosted on Databricks Apps, and can be
managed from the Databricks SDK
([Agent Bricks platform post](https://www.databricks.com/blog/agent-bricks-governed-enterprise-agent-platform)).
Custom agents can also use any harness (LangGraph, OpenAI Agents SDK, Claude Code SDK) and deploy
to Apps with MLflow tracing
([Agent Bricks at DAIS 2026](https://www.databricks.com/blog/agent-bricks-dais-2026)). The build
should pick one path and be able to say why in the deep dive.

## Related

- [Build challenge](build-challenge.md)
