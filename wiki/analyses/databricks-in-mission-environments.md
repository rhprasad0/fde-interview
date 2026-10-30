# How Databricks is deployed in mission environments, and what it means for the MCP path

**Question (Ryan, 2026-10-30):** Before deciding how the agent reaches Databricks, how is
Databricks actually set up in federal mission environments? Managed MCP sounds like functionality
the government may not have yet.

**Answer in one line:** managed MCP is inside the FedRAMP High boundary on AWS GovCloud, but only
the workspace endpoints (Genie Agent, Unity Catalog functions, AI Search); the newer Unity
Gateway `system.ai` MCPs, Supervisor Agent, AI Functions, and Lakebase are not. AWS and Databricks
jointly publish a public-sector reference architecture that puts AgentCore Gateway in front of
those Databricks MCP servers, and AgentCore itself reached GovCloud in May 2026. So the
mission-realistic pattern is exactly the layered one we chose, with one change: front the
Databricks MCP endpoints with AgentCore Gateway rather than calling them directly.

## Where federal Databricks runs

- **Two GovCloud environments.** Databricks for AWS GovCloud (FedRAMP High, non-DoD) and Databricks
  for AWS GovCloud DoD (IL5, connected to NIPRNet), both in `us-gov-west-1`, operated by US citizens
  on US soil ([GovCloud doc](https://docs.databricks.com/aws/en/security/privacy/gov-cloud),
  [IL5 trust page](https://www.databricks.com/trust/compliance/department-of-defense-impact-level-5)).
  FedRAMP High authorization came 2025-02-27; IL5 provisional authorization 2024-11-18
  ([press release](https://www.databricks.com/company/newsroom/press-releases/databricks-achieves-fedramp-high-authorization-aws-govcloud)).
  Databricks claims 80% of federal executive departments as customers (same release).
- **Serverless is still Public Preview in GovCloud** for SQL warehouses, notebooks, jobs, and
  pipelines, and the IL5 trust page says serverless "is not currently covered for any DoD Impact
  Level" ([FedRAMP High doc](https://docs.databricks.com/aws/en/security/privacy/fedramp-high)).
  Our serverless-only demo is ahead of what an IL5 shop can run today; say so if asked.
- **Genie, Assistant, and Foundation Model API went GA in GovCloud on 2026-01-14 and 2026-02-12**,
  with Claude Sonnet 4.5 as the first FMAPI model ([release notes](https://docs.databricks.com/aws/en/release-notes/gov-cloud/2026),
  [blog](https://www.databricks.com/blog/aibi-genie-foundational-model-api-and-databricks-assistant-now-generally-available-aws)).
  Then, starting 2026-09-19, Anthropic models were removed from IL5-selected workspaces
  ([IL5 doc](https://docs.databricks.com/aws/en/security/privacy/il5)). Genie Code requests in
  GovCloud route to Azure OpenAI in Azure Government (GovCloud doc).
- **Mission precedent for MCP on Unity Catalog.** FDA moved to Databricks on AWS GovCloud in 2025,
  acting as FedRAMP High sponsor; its ELSA platform reached 85% of 16,000 staff and "layers MCP
  servers on top of Unity Catalog" so staff build their own agents
  ([FDA blog](https://www.databricks.com/blog/how-fda-built-ai-platform-85-its-staff-now-use-daily),
  [HALO blog](https://www.databricks.com/blog/how-fda-building-secure-ai-ready-data-foundation-databricks-government)).

## Feature availability in the FedRAMP High boundary (read 2026-10-30)

From the feature table on the [FedRAMP High page](https://docs.databricks.com/aws/en/security/privacy/fedramp-high);
the [IL5 page](https://docs.databricks.com/aws/en/security/privacy/il5) matches on every row below.

| Available | Not available |
|---|---|
| Managed MCP Servers (workspace endpoints) | Genie One MCP (`system.ai.genie_one_mcp` via Unity Gateway) |
| Agent Framework on-behalf-of-user authorization | Supervisor Agent (Agent Bricks) |
| Unity AI Gateway, Unity Gateway Skills, budgets | Unity Gateway Service Policies |
| Model Serving: pay-per-token foundation models, external models | AI Functions, `ai_query`, Agent Bricks AI Functions, Knowledge Assistant |
| Genie One, Genie Agents, Genie Code, metric views | Genie Ontology snippets, Genie Inspect Answer |
| Databricks Apps (incl. on-behalf-of, OpenTelemetry) | Lakebase (all variants) |
| Palantir Federation | External Tool Calling for Agents |
| Serverless SQL, jobs, notebooks (Public Preview) | Databricks Marketplace, Partner Connect |

Three consequences for our build:

1. **The MCP endpoints to use are the workspace ones** (`/api/2.0/mcp/genie/{space}`,
   `/api/2.0/mcp/functions/{catalog}/{schema}/{fn}`), which are Public Preview in commercial and
   present in GovCloud. The `system.ai` MCPs through Unity Gateway are the newer path Databricks
   now recommends commercially ([built-in MCPs](https://docs.databricks.com/aws/en/agents/mcp-tools/built-in-mcp-services))
   but are not in the federal boundary. Note the Genie One beta endpoint `/api/2.0/mcp/genie`
   (no space id) reaches end of life 2026-11-30 ([Genie MCP doc](https://docs.databricks.com/aws/en/agents/mcp-tools/genie-mcp)).
2. **No `ai_query` in GovCloud.** The one in-platform AI function we planned (classifying
   separation reasons) would not run in a mission workspace. Keep it as a commercial-only
   flourish or drop it; the FWD file already carries `separation_category`, so the use case is weak anyway.
3. **No Lakebase.** The write-back stretch goal was already deprioritized on cost; this settles it.
   Later the same day write-backs were dropped entirely: the agent is read-only (`DECISIONS.md`).

## The published pattern: AgentCore Gateway in front of Databricks MCP

AWS's public-sector blog (2026-07-14) describes a regulatory-processing agent as "a gateway
pattern: AgentCore handles agent orchestration, authentication, and memory, and Databricks provides
the data processing, extraction, governance, and custom tooling layer." The agent on AgentCore
Runtime calls AgentCore Gateway, which aggregates Lambda business rules and "Databricks-managed MCP
servers, with tool and data access enforced by Unity Catalog" (Genie, AI Search, Unity Catalog
functions, plus custom MCP servers on Databricks Apps) into one MCP endpoint
([AWS blog](https://aws.amazon.com/blogs/publicsector/accelerate-regulatory-package-processing-with-agentic-ai-on-aws/)).
That is our architecture with a Gateway added.

AgentCore side, in GovCloud:

- AgentCore launched in AWS GovCloud (US-West) on 2026-05-05 with Runtime, Gateway, Identity,
  Observability, and Evaluations; Memory, Policy, and Managed Harness followed 2026-08-07
  ([What's New](https://aws.amazon.com/about-aws/whats-new/2026/05/bedrock-agentcore-launch-aws-govcloud-us/),
  [What's New](https://aws.amazon.com/about-aws/whats-new/2026/08/agentcore-memory-policy-harness-govcloud/)).
  Runtime holds FedRAMP High (now "Class D") authorization ([GovCloud newsletter](https://aws.amazon.com/govcloud-us/newsletter/newsletter-issue-07/)).
  Bedrock in GovCloud serves Anthropic Claude among seven model families (same newsletter).
- Gateway Policy writes natural-language rules that compile to Cedar with default-deny and are
  evaluated on every tool call, with decisions in CloudWatch and CloudTrail (newsletter). This is
  the "policy outside agent code" story a Palantir-literate panel will recognize.
- Gateway outbound auth to an MCP target supports OAuth client credentials, authorization code,
  token exchange (on-behalf-of), and API key ([outbound auth](https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/gateway-outbound-auth.html)).
  Token exchange would carry the user's identity to Databricks, but it needs Databricks's OAuth
  endpoint to accept the exchange, which is unverified. Client credentials with a Databricks
  service principal is the safe one-week path; Unity Catalog grants on the service principal
  still bound what the agent can reach.

## What this changes

- **Decision 1 (MCP path).** Recommend AgentCore Gateway fronting the workspace MCP endpoints,
  not direct calls. Reasons: it is the published AWS-plus-Databricks public-sector pattern, it is
  the only shape where Gateway Policy exists, and it uses the MCP endpoints that are inside the
  FedRAMP High boundary. Cost is cents ([cost estimate](build-cost-estimate.md)). Trade-off: with
  client-credentials outbound auth the Databricks caller is a service principal, so Genie usage is
  billed rather than free, and the on-behalf-of story becomes "configured in production via token
  exchange" rather than demonstrated. Say that plainly.
- **Model decision.** The IL5 removal applies to Databricks Model Serving only. Claude stays
  FedRAMP High on Bedrock GovCloud (select models IL4 and IL5), on Vertex, and in Claude for
  Government, and DHS has approved it since 2023. The build keeps Claude Haiku 5.5 as primary
  with GPT-6 Luna as the outage fallback (`DECISIONS.md`, 2026-10-30); the fallback doubles as
  the portability answer for a client whose boundary excludes one vendor. Deploy-day swap is the
  Strands provider from the vendor API to Bedrock.
- **Domain model decision.** Palantir Federation is in the GovCloud boundary, which supports the
  thesis that the Firm's clients run Palantir above Databricks ([synthesis](../synthesis.md)).
- **Drop `ai_query`; the agent is read-only.** See consequences 2 and 3 above.

## Not verified

- Whether Databricks workspace OAuth supports RFC 8693 token exchange as an AgentCore Gateway
  outbound target. If it does, on-behalf-of through Gateway is a day-four upgrade.
- Whether the Genie Agent workspace MCP endpoint is billed differently from Genie One when called
  by a service principal in a trial workspace.
- The commercial us-east-1 workspace has features GovCloud lacks; the demo should avoid relying
  on anything in the right-hand column above so the "this runs in GovCloud" claim holds.
