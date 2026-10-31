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
- **Amended 2026-10-31:** demand comes from the USAJOBS Historic JOA API, not Search. It needs no
  key, covers every DHS announcement since September 2025 with its status and close date (on
  2026-10-31, 427 of 13,136 had status "accepting applications" and a close date not yet passed;
  status alone lags, 297 more carried it after closing), so the Search API would add a second
  copy of the open ones. The Search key stays in `challenge/.env`, unused
  ([spec 02](challenge/specs/02-one-time-load.md)).
- **Amended 2026-10-31 (spec 03):** "open on a date" is `open_date <= date AND close_date >= date`.
  `opening_status` is the status on pull day only; for 2026-08-01 it returns 724 postings against
  551 actually open, missing 503 that have since closed. Status adds information only on pull day.
- **Amended 2026-10-31 (spec 03, Ryan):** a fourth source, the Census Bureau 2025 Gazetteer
  places file (one interior point per place, 32,350 rows, no key), for approximate map geometries.
  It matches about 88% of DHS duty-station cities by exact name; the rest fall to a state centroid
  ([spec 03](challenge/specs/03-semantic-layer.md)).

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

## 2026-10-30  Evaluation: plain harness to a Delta table, AI/BI dashboard on top, MLflow as a stretch

- **Context:** "how do you know it works" is the question that decides FDE deep dives
  ([playbook](wiki/analyses/fde-build-challenge-playbook.md)). Ryan is new to Databricks and
  judged MLflow a week-one learning cost that the panel will not credit; the number wins, not
  the library.
- **Chosen:** 20 to 30 user questions with answers computed by SQL against the silver tables,
  stored as a Delta table. A plain Python harness in a Databricks notebook invokes the AgentCore
  endpoint three times per question, applies deterministic scorers (numbers within tolerance,
  required caveat present, no citation to a nonexistent row) plus one LLM judge for narrative
  faithfulness, and writes per-question, per-run rows to a Delta table. The AI/BI dashboard over
  that table shows pass^1, pass^3, the question-by-run heatmap, failure categories, provider
  served, tool error rate, latency, and cost. Acceptance bar pass^3 of 80%
  ([agent evaluation](wiki/concepts/agent-evaluation.md)).
- **Rejected:** `mlflow.genai.evaluate()` as the harness (first choice; Databricks-native and
  thirty lines once learned, but a dependency on an unfamiliar API during the only week there is;
  it becomes a day-five stretch that wraps the same harness); running the harness on a laptop
  (works, but truth SQL and result writes both live in Databricks, so the notebook is less
  plumbing); ad-hoc spot checks (no number to defend).
- **Revisit:** if the core is green by day five, wrap the harness in MLflow and log traces to a
  Unity Catalog trace table; if the notebook's boto3 call to AgentCore fights IAM, run the harness
  locally and push results through the Statement Execution API.
- **Superseded:** the earlier version chose MLflow as the harness; see git history.

## 2026-10-30  Agent layer: Strands Agents SDK on Amazon Bedrock AgentCore Runtime

- **Context:** with the agent layered above Databricks, it needs a home that is real
  infrastructure, cheap, and familiar enough to learn in days alongside Databricks.
- **Chosen:** Strands Agents (Python) with the `AnthropicModel` provider and `OpenAIModel` as
  fallback (`pip install 'strands-agents[anthropic,openai]'`; model decision below), deployed to
  AgentCore Runtime. AgentCore supplies session isolation, built-in tracing, consumption pricing,
  and MCP client support ([Strands Anthropic provider](https://strandsagents.com/docs/user-guide/sdk/model-providers/anthropic/),
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
- **Correction (2026-10-30 evening):** Unity Catalog functions cannot write; Python UDFs are
  sandboxed and scalar-only, SQL UDFs are read-only. Rather than replace them with procedures,
  Ryan dropped write-backs altogether: the layer is read-only, the agent holds no write grant
  anywhere in Databricks, the Lakeflow job owns every write, and recommended actions live in the
  briefing text for the committee to act on. Autonomy level "assistant." Functions stay for every
  graded read ([pre-spec gaps](wiki/analyses/pre-spec-gaps.md)).

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
  Briefings are not synthetic: they are agent output written to Delta by the Lakeflow job, not
  by the agent (write-backs dropped later the same day). The eval set is computed by SQL against
  real tables, not synthesized.
- **Revisit:** if OMB Table 16.1 cannot be crosswalked to the home agency in an hour, scale to
  the agency's own trailing headcount instead and say so; if the panel includes an agency human
  capital person, offer to swap in their real plan shape.
- **Amended 2026-10-31 (spec 03):** no crosswalk needed, DHS is a department column in Table
  16.1 (FY2027 edition: 227,000 FTE for FY2026, 224,000 for FY2027, estimates). The table lives in
  the `synthetic` schema next to the imputed tables. Planned hires replace non-DRP trailing
  separations plus any growth to the FTE target, split evenly over four quarters; the two stress
  cells are TSA 1802 and CBP 1895 in FY2026 ([spec 03](challenge/specs/03-semantic-layer.md)).

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
- **Added (2026-10-30 evening):** inbound auth to the Gateway is IAM SigV4 from the Runtime role
  via `mcp-proxy-for-aws`, no Cognito. There is no write target; the agent is read-only
  ([pre-spec gaps](wiki/analyses/pre-spec-gaps.md)).

## 2026-10-30  Model: Claude Haiku 5.5 primary, GPT-6 Luna as the outage fallback

- **Context:** the challenge allows Claude, Gemini, or GPT. Ryan holds Anthropic API credits and
  a funded OpenAI account. The pass^3 bar means roughly 75 agent runs per eval pass, so the model
  must be cheap and fast. Claude is approved at DHS, the home agency, and is FedRAMP High on
  Bedrock GovCloud, Vertex, and Claude for Government; the only restriction found is Databricks
  Model Serving dropping Anthropic models in IL5 workspaces on 2026-09-19, which our architecture
  never touches because the model is called from the agent layer
  ([mission environments](wiki/analyses/databricks-in-mission-environments.md)).
- **Chosen:** Claude Haiku 5.5 (`claude-haiku-5-5`) through the Anthropic API via the Strands
  `AnthropicModel` provider, with prompt caching on. GPT-6 Luna (`gpt-6-luna`, confirm the API id
  on day one) through the OpenAI API via `OpenAIModel` as the fallback, selected automatically
  when the Anthropic API returns a connection error, a 5xx, or an overloaded response. One
  constructor builds the model; every trace and every eval result row records which provider
  served the run, so a pass^3 computed across a fallover is labeled, not silent. The fallback is
  also the portability demonstration: a client whose boundary excludes one vendor changes one
  config value.
- **Rejected:** Luna as primary (decided earlier today and reversed; it was chosen for DoD
  portability, but Claude's federal authorizations are current and the DoD concern is answered by
  the fallback and by Bedrock GovCloud on deployment); Gemini (no advantage here); a larger
  Claude model as primary (75 runs per eval pass; use it only if Haiku fails the eval on
  reasoning rather than on tools).
- **Revisit:** if Haiku's pass^3 is under 80% with failures traced to the model rather than the
  tools, rerun the eval on the fallback and on a larger Claude model and pick on the numbers; if
  a client boundary excludes Anthropic, flip the config and say so.
- **Superseded:** the earlier version of this entry chose Luna as primary; see git history.

## 2026-10-30  Agent topology: one agent with governed tools, accepted at pass^3 of 80% or better

- **Context:** the earlier plan was a supervisor with four workers. Ryan judged the split
  unjustified by the problem and set the demo-day bar as an eval dashboard showing pass^3 of at
  least 80%, meaning each golden question passes all three independent runs.
- **Chosen:** a single Strands agent whose tools are the Databricks workspace MCP endpoints
  behind AgentCore Gateway: Unity Catalog functions for every number the eval grades (attrition
  rate, posting coverage, length-of-service distribution per cell), the Genie Agent for open
  exploration the eval does not grade, and skill files for the briefing format and code lists.
  Orchestration lives in one Lakeflow job: ingest the monthly files, refresh the semantic layer,
  run the scheduled briefing, run the eval three times, write the dashboard tables. The eval
  dashboard is an AI/BI dashboard over a Delta table of per-question, per-run results showing
  pass^1, pass^3, a question-by-run heatmap, and failure categories. A run passes a question only
  if every scorer passes: numbers within tolerance of SQL truth, required caveat present, no
  citation to a nonexistent row, and one LLM judge for narrative faithfulness. pass^k is the
  tau-bench definition: the agent succeeds on all k independent trials.
- **Rejected:** supervisor plus workers (all workers read the same Unity Catalog layer under the
  same service principal, so they differ in neither tools nor permissions; every handoff adds a
  failure point, and pass^3 of 80% needs about 93% per run, which handoffs erode); Genie as the
  source of graded numbers (its generated SQL varies run to run); an ingest agent (a data-quality
  step in the job does the same work deterministically).
- **Revisit:** if pass^3 lands under 80% on day five, report the measured number with the
  heatmap and the failing questions rather than tune the bar; if a question genuinely needs a
  different trust boundary (for example a tool that writes), add a second agent for that boundary
  only and log it.

## 2026-10-30  Region: us-east-1 for Databricks and AgentCore

- **Context:** previews and AgentCore features are region-gated.
- **Chosen:** `us-east-1` for both. The cost estimate is priced there and Databricks previews
  land there first.
- **Rejected:** `us-west-2` (no feature we need is exclusive to it).
- **Revisit:** if Managed MCP Servers or AgentCore Gateway is missing in `us-east-1` on day one,
  move before creating anything else.
- **Superseded 2026-10-31** by "Region: us-west-2" below.

## 2026-10-30  Demo shape: the eval dashboard leads, one live run supports it

- **Context:** the 15-minute demo and 30-minute deep dive need a center of gravity. Ryan wants
  demo day to be a deep dive on evals.
- **Chosen:** open on the AI/BI eval dashboard (pass^1, pass^3, question-by-run heatmap, failure
  categories), walk one failing question through its traces, then run one briefing question live
  against real tables. A full run is recorded the night before as a disclosed fallback.
- **Rejected:** a fully live tour of the agent (reliability is the story, so the measured number
  comes first); a fully cached demo (undisclosed caching found out costs everything).
- **Revisit:** if the live step is slow or depends on an external API, cache that step only and
  say which.

## 2026-10-30  Repository: everything stays in this repo

- **Context:** the code walkthrough needs a medium, and the repo is public with the company name
  kept out.
- **Chosen:** the build (agent, Databricks assets, eval) lives in this repo under `challenge/`,
  protected by the same forbidden-terms hooks and gitleaks CI. The panel sees one repo with the
  wiki, the decision log, and the code. Screen share it in the deep dive.
- **Rejected:** a second repo for code (splits the decision trail from the code it explains);
  screen share only (the panel cannot read anything after the call).
- **Revisit:** if the Firm asks that the build stay private, make this repo private for the
  interview window.

## 2026-10-30  Evaluation tooling: MLflow pass^3 dashboard plus AgentCore Evaluations on the traces

- **Context:** the pass^3 dashboard is the defended number. AgentCore Evaluations can score the
  same agent traces inside AWS for under a dollar.
- **Chosen:** both. MLflow and the Delta results table carry pass^3; AgentCore Evaluations scores
  the Runtime traces on correctness and goal success as a second, independent read. Build it on
  day five, after the core demo is green.
- **Rejected:** MLflow alone (fine, but loses the "how would you evaluate without Databricks"
  answer); AgentCore alone (loses the Databricks tracing story).
- **Revisit:** if the two disagree materially, say so on the dashboard and explain which scorer
  is wrong and why.

## 2026-10-30  Home agency: Department of Homeland Security

- **Context:** the demo needs one agency with a large 2025 decline, many components, and real
  USAJOBS volume.
- **Chosen:** DHS. TSA (`HSBC`), CBP (`HSBD`), and ICE (`HSBB`) appear in both OPM and USAJOBS
  data with matching codes, the panel knows the components, and the Firm's Palantir workforce
  posting is DHS-flavored ([data sources](wiki/analyses/candidate-data-sources.md)).
- **Rejected:** Veterans Affairs (largest volume, but one component dominates); Treasury (IRS is
  interesting, few other components).
- **Revisit:** if DHS data has a coverage gap in the demo month, switch to Treasury and say so.

## 2026-10-30  Observability: CloudWatch and CloudTrail are the audit record; Databricks shows governance

- **Context:** an agent needs an audit log. AgentCore writes one by default, and Ryan does not
  want to learn MLflow tracing in week one.
- **Chosen:** AgentCore Observability with ADOT instrumentation sends every session, model call,
  and tool call with arguments and results to CloudWatch; CloudTrail data events record every
  Gateway policy decision. That is the audit record. On the Databricks side the evidence is Unity
  Catalog grants (read-only service principal), lineage, `system.query.history` for the SQL each
  function ran, and the eval results table. The eval harness writes the AgentCore session id into
  each results row so a dashboard cell links to its CloudWatch trace
  ([observability minimum](wiki/analyses/observability-governance-minimum.md)).
- **Rejected:** MLflow traces in a Unity Catalog trace table as the audit record (documented and
  one line of code, but a second trace system to learn and reconcile; day-five stretch alongside
  the MLflow harness); a function-written audit table (functions cannot write).
- **Revisit:** if a panelist asks for agent traces inside Databricks, the day-five stretch is the
  answer; if CloudWatch trace retention or cost surprises, shorten retention.

## Databricks surface, decided by omission

Four things done properly: bronze and silver Delta tables loaded once by a notebook job from a
Unity Catalog volume (one-time since 2026-10-31; the recurring Lakeflow job starts at silver); Unity Catalog
governance (read-only service principal, grants, lineage, a Genie space over the semantic views); the
workspace MCP endpoints; an AI/BI dashboard over the eval table. Skipped and named as skipped:
MLflow (day-five stretch), stored procedures, Lakebase, Databricks Apps, in-platform AI
functions, Agent Bricks.

## 2026-10-31  Signup: direct express trial, not AWS Marketplace

- **Context:** a serverless workspace puts nothing in the AWS account, so Marketplace only linked
  billing, and the CLI identity at hand was the Organization's management account.
- **Chosen:** sign up at databricks.com with no payment method. Spending is capped at the trial
  credits, the management account stays out of it, and there is no subscription to cancel at
  teardown ([spec 01](challenge/specs/01-databricks-setup.md)).
- **Rejected:** AWS Marketplace (rolls to pay-as-you-go on the AWS account after the trial).
- **Revisit:** if the interview falls after the trial end date; add a payment method and lean on
  the budgets.
- **Amended 2026-10-31:** a payment method was added to try to lift the egress block (see Ingest,
  below). It did not lift it. The spend cap is gone, the $25 and $45 budget alerts are the guard,
  and the 2026-11-14 trial end no longer stops the workspace.

## 2026-10-31  Region: us-west-2 for Databricks and AgentCore

- **Context:** express setup offered no region choice and placed the workspace in `us-west-2`.
- **Chosen:** keep it, and put AgentCore in `us-west-2` too so the agent and its data share a
  region. Databricks lists MCP servers, serverless, Lakebase, and hosted models as supported in
  both regions ([region support](https://docs.databricks.com/aws/en/resources/feature-region-support));
  AgentCore Runtime, Gateway, Identity, Observability, and Evaluations are all in `us-west-2`
  ([AgentCore regions](https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/agentcore-regions.html)).
- **Rejected:** upgrading the trial to create a `us-east-1` workspace (removes the spend cap for
  no feature gain).
- **Revisit:** if a preview needed later turns out to be missing in `us-west-2`.

## 2026-10-31  Terraform for the workspace objects the agent's governance rests on

- **Context:** the read-only service principal and its grants are the governance story, and
  clicking them in leaves nothing to review.
- **Chosen:** `challenge/infra/main.tf` (Databricks provider, CLI-profile sign-in, local
  gitignored state) manages the warehouse settings, catalog, schemas, service principal,
  entitlement, grants, and secret scope. The agent gets `EXECUTE` on the `semantic` schema rather
  than per function, so the schema is the boundary of what it can call. The OAuth secret, secret
  values, budgets, preview toggle, and SQL objects stay out: the secret resource cannot set scopes
  and would put the secret in state, and budgets need an account-level provider. Later workloads
  (Lakeflow job, dashboard) go in Databricks Asset Bundles
  ([spec 01](challenge/specs/01-databricks-setup.md)).
- **Rejected:** SQL `GRANT` statements plus console clicks (spec 01 as first written);
  function-level `EXECUTE` grants (each new function would need a grant change and a second apply).
- **Revisit:** if the provider fights the trial workspace for more than an hour, fall back to the
  SQL in the first version of spec 01.
- **Amended 2026-10-31 (spec 03):** `SELECT` on `semantic` added so Genie can query the semantic
  views as the service principal, and the spec 01 `USE_SCHEMA` on `silver` removed: functions and
  views read `silver` and `synthetic` with their owner's rights (spec 01 step 9), so that grant
  gave the agent nothing readable and only muddied the story. Four grants remain, all on the
  catalog and `semantic`; the agent holds nothing on `bronze`, `silver`, or `synthetic`.

## 2026-10-31  Ingest: land the source files in a Unity Catalog volume from a laptop

- **Context:** serverless compute on this account refuses DNS for `data.opm.gov` and
  `data.usajobs.gov`; `system.access.outbound_network` logs each lookup as a DNS `DROP`. Network
  policies need the Enterprise tier, and adding a payment method did not lift the block. A
  Databricks employee ties it to account verification, not billing
  ([forum thread](https://community.databricks.com/t5/administration-architecture/serverless-egress-blocked-despite-full-access-network-policy/td-p/173281);
  [spec 01 results](challenge/specs/01-results.md)).
- **Chosen:** a laptop script pulls the OPM FWD Parquet files and the USAJOBS Search results and
  uploads them with `databricks fs cp` to a volume in `workforce.bronze`; the Lakeflow job loads
  bronze and silver from the volume. The USAJOBS key stays in `challenge/.env`. Closed egress
  becomes part of the governance story: workspace compute reaches only allowlisted hosts, and
  every refused lookup is audited.
- **Rejected:** waiting for account verification (support's timeline, with four days to the
  freeze); a classic-compute workspace on a linked AWS account (a second workspace plus VPC and
  cross-account IAM, for one download step).
- **Revisit:** if the account is verified before the freeze, move the pull into the Lakeflow job
  and the key into the `workforce` secret scope.
- **Amended 2026-10-31 (Ryan):** the load is one-time, no refresh. Twelve months of OPM files
  ending August 2026 (September is due 2026-11-04, after the freeze) and the DHS Historic JOA to
  the day of the pull land once in the volume; a SQL notebook run once as a job writes bronze and
  silver. The recurring Lakeflow job (spec 05) starts at silver. The egress blocker is documented
  and that is enough; the deployed version of this step is the Lakeflow pull described above
  ([spec 02](challenge/specs/02-one-time-load.md)).

## 2026-10-31  Imputation: synthetic location and pay for OPM-redacted rows, in a `synthetic` schema

- **Context:** OPM masks location, pay, and bargaining unit together on 76% of DHS employee
  records (August 2026), by occupation: every TSA screener, CBP officer, and Border Patrol agent.
  Location is one of the four slices in the problem statement
  ([redaction profile](wiki/analyses/opm-redaction-and-imputation.md)).
- **Chosen (Ryan):** imputed copies of `employment`, `separations`, and `accessions` in a new
  `synthetic` schema. Location and pay are drawn from USAJOBS postings for the same component,
  series, and grade, and every row is flagged `location_imputed` and `pay_imputed`. The agent reads
  the copies through `semantic` and says so when an answer rests on an imputed value. `silver`
  is untouched. Bargaining unit stays as published. Specified in spec 03.
- **Rejected:** the agent answers "not published" for redacted fields (honest, but it loses the
  location slice for most of DHS); borrowing values from unredacted records (the redacted series
  have no unredacted records, so screeners would get analysts' offices and pay); tables in `silver`
  with an `_imputed` suffix (puts published and synthetic data in one schema).
- **Revisit:** if the masking test on FEMA and CISA lands far from the truth, or if the agent
  cannot reliably disclose imputed values, fall back to "not published" for redacted rows.
  **Withdrawn 2026-10-31 (Ryan):** the demo is "more art than science"; the masking result is
  recorded and disclosed but changes nothing, and the implementing session needs no sign-off on it.
- **Amended 2026-10-31 (spec 03):** three of the nineteen redacted location columns are imputed
  (city, state, state abbreviation), the three a posting supplies; the rest stay `REDACTED`. The
  draw is a hash of the row's published columns plus its position among identical rows, so a
  rerun reproduces the tables; draws are independent per snapshot (no id links a person across
  months). Pay is uniform within the matched posting's salary range, matched on pay plan and
  zero-padded grade. "Far from the truth" is defined: distribution overlap of imputed versus true
  state under 0.5 on FEMA or CISA ([spec 03](challenge/specs/03-semantic-layer.md)). Later the
  same day the bar was withdrawn (Revisit, above) and approximate point geometries were added:
  every row with a city gets the Census Gazetteer place point, or the state centroid, with a
  `geo_precision` flag, so the spec 05 dashboard can draw a map (Data, amended).

## 2026-10-31  Counting: separations and accessions by effective month across all files

- **Context:** each monthly OPM file carries actions effective up to two years earlier, and rows
  have no action id. Spec 02 left the choice between counting by the reporting file and counting
  by `effective_month` ([spec 02 results](challenge/specs/02-results.md)).
- **Chosen:** count by `effective_month` across all twelve files. Rows identical on every
  published column that appear in more than one file are the only detectable restatements: 0.8%
  of DHS separation rows, 9% of accession rows (mostly identical new hires in one month, not
  restatements). A restatement that changes a column is invisible, so this is evidence, not a
  bound. The latest months are right-censored: most of a month's late-reported actions arrive in
  the next two files, so trailing counts ending in the demo month will grow. Every counting
  function states both.
- **Rejected:** counting by reporting month (no restatement risk, but "left in January" would
  mean "reported in January", which is not what the user asks); counting only rows effective in
  the reporting month (drops 25% of rows, under half in two months).
- **Revisit:** if OPM adds an action id, deduplicate on it; if a later file's restatement is ever
  shown to exceed a few percent for separations, switch to reporting month and say so.

## Build-week items, not decisions

- Code freeze: last commit to this repo by Thursday 2026-11-05 at 17:00. Everything after that is
  rehearsal. No interview date yet; the recruiter is notified on completion.
- Write the 20 to 30 golden questions first, then derive the Unity Catalog function list from
  them. Every graded number needs a function behind it.
- Confirm the `gpt-6-luna` API id and the OMB Table 16.1 crosswalk for DHS.
- Day one: enable the Managed MCP Servers workspace preview; confirm which SKU the MCP functions
  server bills to (function tools run on serverless generic compute); measure Genie Agent MCP
  latency under the service principal.
- Write the model fallback as a small Strands `Model` wrapper that delegates to Anthropic and
  retries once on OpenAI for connection errors, 5xx, and overloaded responses, tagging the trace
  with the provider. Test it by pointing the Anthropic base URL at a dead port.
