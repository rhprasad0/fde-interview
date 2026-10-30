# Multi-agent orchestration

Splitting an agentic system into several LLM-driven workers coordinated by a supervisor, where
each worker owns a distinct tool set or data source. Named by the
[build challenge email](../sources/build-challenge-email.md) as one example of "sufficient
complexity."

## When the split is justified

A multi-agent design earns its place when workers differ in tools, data, or permissions, not when
one prompt is cut into pieces for show. In the chosen build, the workers differ on all three
([analysis](../analyses/build-challenge-problem-selection.md)):

| Worker | Tools and data | Why separate |
|---|---|---|
| Ingest / data-quality checker | OPM and USAJOBS APIs, Unity Catalog volume, Delta tables | Runs before analysis; owns schema-evolution handling |
| Workforce analyst | Genie over silver tables, UC functions via MCP | Read-only, governed by Unity Catalog permissions |
| Hiring-market analyst | USAJOBS search | Different API, different rate limits |
| Briefing writer | Skills for format and OPM code lists | No data access; only consumes the analysts' findings |

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
