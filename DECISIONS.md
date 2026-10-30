# Decision log

One entry per decision that shaped the build. Each entry names the alternative rejected and the
condition that would reopen it, so every "why did you do X" in the deep dive has a three-sentence
answer. Newest at the bottom. Keep entries short; link to the wiki for the reasoning.

Format:

```
## YYYY-MM-DD  <decision in one line>
Context:   why a decision was needed
Chosen:    what we did
Rejected:  the strongest alternative(s) and why not
Revisit:   what evidence would change this
```

## 2026-10-30  Problem: federal workforce-risk briefing agent for an agency CHCO

- **Context:** the build challenge asks for a named user, an impact story, and real API data
  within one week ([email](wiki/sources/build-challenge-email.md)).
- **Chosen:** help a Chief Human Capital Officer or workforce-planning analyst see where
  attrition-driven capability gaps are forming (sub-agency x occupation x location x tenure) and
  whether open postings target them.
- **Rejected:** agency spending intelligence (same mechanics, weaker urgency); cyber risk fusion
  (the Firm already sells an accelerator there); critical-minerals supply chain (no clean public
  data). Scoring in [problem selection](wiki/analyses/build-challenge-problem-selection.md).
- **Revisit:** if OPM data access fails on day one, switch to spending intelligence on
  USAspending, which needs no key.

## 2026-10-30  Platform: Databricks on AWS, pay-as-you-go, under $50, torn down after

- **Context:** round one asked whether Ryan can pick up Databricks fast; Ryan wants everything on
  real infrastructure.
- **Chosen:** a full Databricks workspace on AWS via the business-email trial, serverless only,
  two budget alerts, deleted after the interview.
- **Rejected:** Free Edition (restricted egress to an unpublished allowlist, no account console,
  "certain models not available", apps stop after 24 hours); running the agent off-platform and
  only storing data in Databricks (platform would be decorative).
- **Revisit:** if trial credits do not activate or a needed preview is region-gated, fall back to
  Free Edition with off-platform ingestion pushing Parquet to a Unity Catalog volume.
- **Cost check (2026-10-30):** the trial carries up to $400 of credits for 14 days, which covers
  the roughly $60 to $90 of list-price Databricks usage the week needs. The two ways to overspend
  are a SQL warehouse left running ($2.80/hr) and a Lakebase project at its 8 CU default
  ([estimate](wiki/analyses/build-cost-estimate.md)).

## 2026-10-30  Data: OPM Federal Workforce Data API plus USAJOBS Search API

- **Context:** the demo needs live API data a federal panel will recognize.
- **Chosen:** OPM FWD monthly Employment, Accessions, and Separations Parquet files (no auth,
  record level, 2M+ rows) for supply; USAJOBS Search API (free key) for demand.
- **Rejected:** legacy FedScope cubes (superseded, stale); synthetic HR data (weakens the "API
  access" criterion and the impact story); FEVS engagement survey (2025 survey cancelled, no
  current data).
- **Revisit:** if the September 2026 release slips past 2026-11-04, demo on August data and say so.
- **Verified (2026-10-30):** both APIs probed live; the Employment Parquet downloads at 57 MB
  despite the documented 25 MB limit; Separations carries `length_of_service_years` and
  `separation_category`; OPM `agency_subelement_code` equals USAJOBS `hiringAgencyCode` (TSA is
  `HSBC` in both). FEVS was formally discontinued 2026-10-29. OMB Table 16.1 budgeted FTE is the
  one enrichment to add if the core is green ([data sources](wiki/analyses/candidate-data-sources.md)).

## 2026-10-30  LLM access: the model is called from the agent layer, Databricks is the governed tool layer

- **Context:** research suggests the Firm's federal clients run the agent layer (Palantir AIP)
  above Databricks, which supplies governed data through Unity Catalog
  ([Palantir-Databricks partnership](https://www.databricks.com/company/newsroom/press-releases/palantir-and-databricks-announce-strategic-product-partnership)).
- **Chosen:** the agent calls the model directly from the agent layer and reaches Databricks only
  through managed MCP servers. Model vendor decided separately below.
- **Rejected:** the model served from Databricks Foundation Model API endpoints as the primary
  path (first choice earlier today; it makes Databricks the agent host, which is not how the
  Firm's stack appears to be layered, and it caps iteration on pay-per-token rate limits).
- **Superseded:** two earlier versions of this entry named a vendor; see git history for the text.

## 2026-10-30  Evaluation: MLflow golden set in Unity Catalog, run with `mlflow.genai.evaluate()`

- **Context:** "how do you know it works" is the question that decides FDE deep dives
  ([playbook](wiki/analyses/fde-build-challenge-playbook.md)).
- **Chosen:** 20 to 30 user questions with answers computed by SQL against the silver tables,
  stored as a Unity Catalog evaluation dataset, scored with built-in judges plus one exact-match
  scorer ([agent evaluation](wiki/concepts/agent-evaluation.md)).
- **Rejected:** ad-hoc spot checks (no number to defend); a third-party eval framework (adds a
  dependency and leaves the Databricks tracing story).
- **Revisit:** if `mlflow.genai.evaluate()` is unavailable in the trial workspace, fall back to a
  notebook that runs the same cases and writes results to a Delta table.

## 2026-10-30  Agent layer: Strands Agents SDK on Amazon Bedrock AgentCore Runtime

- **Context:** with the agent layered above Databricks, it needs a home that is real
  infrastructure, cheap, and familiar enough to learn in days alongside Databricks.
- **Chosen:** Strands Agents (Python) with the `OpenAIModel` provider
  (`pip install 'strands-agents[openai]'`; vendor decision below), deployed to AgentCore
  Runtime. AgentCore supplies session isolation, built-in tracing, consumption pricing, and
  MCP client support ([Strands OpenAI provider](https://strandsagents.com/docs/user-guide/sdk/model-providers/openai/),
  [deploy to AgentCore](https://strandsagents.com/docs/user-guide/sdk/deploy/deploy_to_bedrock_agentcore/),
  [AgentCore Runtime](https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/agents-tools-runtime.html)).
- **Rejected:** Palantir AIP Developer Tier as the agent layer (mirrors the Firm's stack most
  closely, but two unfamiliar platforms in one week is too much, and user-only auth complicates
  a server-side agent); Databricks App or Agent Bricks Supervisor (makes Databricks the agent host,
  which blurs the layer story); a vendor agent SDK on a bare container (works, but AgentCore gives
  tracing and identity for free and is the AWS-native answer a federal panel will recognize).
- **Revisit:** if AgentCore Runtime costs or region gating threaten the $50 budget or the
  timeline, run the same Strands agent on Lambda or ECS; the agent code does not change.

## 2026-10-30  Domain model: an ontology-like semantic layer in Unity Catalog

- **Context:** the Firm's clients run Palantir, whose Ontology (object types, links, Actions)
  is what agents are bounded to. The panel will think in those terms.
- **Chosen:** model the workforce domain as named object types (Agency, SubAgency, Occupation,
  DutyStation, WorkforceSnapshot, Separation, Accession, JobPosting) as governed Unity Catalog
  tables and views with column comments; links as documented keys; metrics (attrition rate,
  vacancy coverage) as Unity Catalog functions or metric views; the few write-backs the agent may
  perform (flag a gap, add a briefing item) as Unity Catalog functions that play the role of
  Actions. The agent touches only this layer over MCP, never raw bronze tables. Genie's semantic
  layer sits on top for natural-language questions.
- **Rejected:** letting the agent write SQL against raw tables (fast, but no governance story and
  nothing to point at when asked "where is your ontology"); a Palantir Ontology proper (see
  agent-layer decision).
- **Revisit:** the object-type list once the eval questions exist; drop any type no question
  touches.

## 2026-10-30  User and problem statement: the workforce-planning analyst's quarterly variance brief

- **Context:** the pitch must say why this problem, who the user is, and what impact to expect.
- **Chosen:** operator is a GS-13 to GS-14 workforce-planning analyst in an agency human capital
  office; beneficiary and buyer is the CHCO; the Strategic Hiring Committee consumes the output.
  The problem is the quarterly Annual Staffing Plan variance explanation and staffing review now
  required of over 80 agencies by OPM's rule effective 2026-11-30, produced by HR offices that
  shrank 18.5% in 17 months. The decision the agent changes: which occupations and locations get
  hiring priority and retention attention this quarter. Positioning: "show where separation-driven
  staffing risk is concentrating, whether advertised hiring is aimed at it, and what needs a
  leader's decision, with traceable numbers and explicit uncertainty"
  ([research](wiki/analyses/user-problem-impact.md)).
- **Rejected:** congressional oversight or GAO analyst (public data is their only data, but they
  are not the Firm's clients); program office director (too narrow for a general demo); framing
  the output as a chatbot (OPM's FWD Chat already does plain-English answers over the public
  data; our differentiation is cross-source, scheduled, governed, plan-aware briefings).
- **Revisit:** if the panel includes someone from an agency human capital office, lead with the
  Annual Staffing Plan and quarterly review vocabulary and let them steer.

## 2026-10-30  Synthetic data: one labeled staffing-plan table, nothing else

- **Context:** the user's job is to explain quarterly variance against the Annual Staffing Plan,
  which every agency keeps private. Public data has no plan at component x occupation x quarter
  grain, so a plan-aware demo needs one from somewhere
  ([data sources](wiki/analyses/candidate-data-sources.md)).
- **Chosen:** a single `staffing_plan` table for the demo's home agency: one row per component,
  occupation series, and fiscal quarter for FY2026 and FY2027 with planned hires and a target
  onboard count, the fields the OMB/OPM hiring-forecast guidance names. Generated by a readable
  rule (planned hires = trailing twelve-month separations per cell, scaled so the FY total lands
  on OMB Table 16.1 budgeted FTE), stored next to the table as a notebook or Unity Catalog
  function. Every row carries `is_synthetic = true` and a `generation_rule` column, and the agent
  prints the label whenever it cites the plan. Two cells get a deliberate 20% under-plan so the
  variance explanation has a real variance to explain. Panel line: "in deployment this is the
  agency's ASP submission; for the demo I generated it from this rule."
- **Rejected:** synthetic competency or skills-gap assessments (would fabricate the thing we say
  the data cannot show, and undercut "capability risk, not proven gap"); synthetic time-to-hire
  per hiring action (second fabricated layer for a metric the decision does not need); anything
  individual-level (PII, out of scope); synthesizing anything the OPM or USAJOBS APIs already
  cover (the rubric scores API data, and the data decision already rejected synthetic HR data).
  Committee decisions and briefing items are not synthetic: they are empty write-back tables that
  fill during the demo. The eval set is computed by SQL against real tables, not synthesized.
- **Revisit:** if OMB Table 16.1 cannot be crosswalked to the home agency in an hour, scale to
  the agency's own trailing headcount instead and say so; if the panel includes an agency human
  capital person, offer to swap in their real plan shape.

## 2026-10-30  MCP path: AgentCore Gateway in front of the Databricks workspace MCP endpoints

- **Context:** the agent needs governed access to Databricks tools, and the panel will judge
  whether the shape matches how agencies run Databricks. Research into the FedRAMP High and IL5
  boundary on AWS GovCloud showed the workspace managed MCP endpoints are inside it while the
  Unity Gateway `system.ai` MCPs are not, and AWS and Databricks publish a public-sector pattern
  with AgentCore Gateway aggregating Databricks MCP servers
  ([mission environments](wiki/analyses/databricks-in-mission-environments.md)).
- **Chosen:** the Strands agent on AgentCore Runtime calls one AgentCore Gateway. Gateway targets
  are the Databricks workspace MCP endpoints for the Genie Agent
  (`/api/2.0/mcp/genie/{space_id}`) and Unity Catalog functions
  (`/api/2.0/mcp/functions/{catalog}/{schema}/{fn}`). Outbound auth is OAuth client credentials
  with a Databricks service principal whose Unity Catalog grants bound what the agent can reach.
  One Gateway Policy rule in natural language, compiled to Cedar, shows policy outside agent
  code. Consequences accepted: Genie usage is billed under the service principal (trial credits
  cover it), and on-behalf-of identity is described as the production path via token exchange
  rather than demonstrated.
- **Rejected:** direct MCP calls from the agent (fewer parts, free Genie under user identity,
  but no policy layer and not the published federal pattern); Unity Gateway `system.ai` MCPs
  (Databricks's commercial recommendation, not in the GovCloud boundary); a custom MCP server on
  Databricks Apps (works in GovCloud, but adds code for tools Databricks already serves).
- **Revisit:** if Databricks OAuth accepts token exchange as a Gateway outbound target, switch
  to on-behalf-of on day four; if Gateway setup eats more than half a day, fall back to direct
  calls and log it.

## 2026-10-30  Model vendor: OpenAI GPT through the OpenAI API

- **Context:** the challenge allows Claude, Gemini, or GPT. Ryan may be deployed to DoD
  customers. Anthropic models were removed from Databricks IL5 workspaces on 2026-09-19, and the
  team is not approved to use the vendor's models on Bedrock, so the panel conversation should not
  turn on a model a DoD client cannot run
  ([mission environments](wiki/analyses/databricks-in-mission-environments.md)).
- **Chosen:** OpenAI GPT called through the OpenAI API from the Strands `OpenAIModel` provider.
  Pin the model id on day one; keep the provider behind one constructor so it is swappable.
  OpenAI's models are also what Genie Code in GovCloud routes to (Azure OpenAI in Azure Government)
  and are served on Bedrock in GovCloud, which is the deploy-day answer if the panel asks.
- **Rejected:** Claude via the Anthropic API (Ryan's daily model and he holds credits, but it is
  the model removed from IL5 and not approved on Bedrock for this team; keep it out of the
  panel-facing story); Gemini (no advantage over GPT here); GPT via Bedrock (not approved for
  this team today, so the API is the path; Bedrock is the production swap).
- **Revisit:** if Bedrock access for OpenAI models is granted, switch the Strands provider to
  Bedrock and nothing else changes; if the OpenAI API rate-limits iteration, use a smaller model
  for the eval loop and the pinned model for the demo.

## Pending

Decisions the build will force in the first two days. Log each when made.

- Worker split: which of the four proposed workers (ingest checker, workforce analyst,
  hiring-market analyst, briefing writer) survive once the eval set exists.
- AWS region: `us-east-1` versus `us-west-2`, driven by Databricks preview and AgentCore
  availability.
- Demo state: fully live versus cached responses for the rehearsed path, disclosed to the panel.
- Code walkthrough medium: public GitHub repo (company name kept out) versus screen share only.
- Evaluation tooling: MLflow golden set (decided) alone, or also AgentCore Evaluations on the
  agent traces.
