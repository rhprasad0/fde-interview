# Observability and governance: the minimum to show on demo day

**Question (Ryan, 2026-10-30):** What observability and governance should the build display at a
minimum?

**Answer in one line:** four dashboard panels (quality, reliability, cost, evidence
completeness), provenance on every number the briefing prints, five governance artifacts that
prove the agent is bounded (grants, lineage, one denied tool call, audit rows, a human-oversight
statement), and a one-paragraph OMB M-25-21 determination. Everything else is logged but not
shown, or skipped with a reason. One finding changes earlier pages: the Databricks tracing
surfaces most docs describe belong to Unity Gateway, which our chosen MCP path bypasses, so the
Databricks-side evidence is Unity Catalog grants, lineage, audit, query history, and MLflow
traces, not the unified trace table.

## What the sources converge on

- **AWS Well-Architected Agentic AI Lens.** Every agent action observable and traceable
  end-to-end on a single trace fabric; agent behavior treated as code (prompts, tool catalogs,
  policies versioned); autonomy paired with proportionate human oversight by named level
  (observer, assistant, autonomous, orchestrator); tool authorization enforced at the protocol
  layer by policy, not by the model's reasoning; decision artifacts stored outside the agent's
  own scope so it cannot alter its record; every logged action carrying its initiating source
  ([design principles](https://docs.aws.amazon.com/wellarchitected/latest/agentic-ai-lens/design-principles.html),
  [AGENTSEC02](https://docs.aws.amazon.com/wellarchitected/latest/agentic-ai-lens/agentsec02.html),
  [AGENTSEC05](https://docs.aws.amazon.com/wellarchitected/latest/agentic-ai-lens/agentsec05.html),
  [AGENTOPS04-BP02](https://docs.aws.amazon.com/wellarchitected/latest/agentic-ai-lens/agentops04-bp02.html)).
- **OMB M-25-21.** High-impact AI is AI whose output "serves as a principal basis for decisions
  or actions that have a legal, material, binding, or significant effect on rights or safety."
  High-impact use requires pre-deployment testing, an impact assessment with independent review
  and signed risk acceptance, ongoing monitoring with traceability, operator training, human
  oversight with a fail-safe, appeals, and user feedback. Every use case, high-impact or not,
  goes in the agency's public AI use case inventory
  ([M-25-21](https://www.whitehouse.gov/wp-content/uploads/2025/02/M-25-21-Accelerating-Federal-Use-of-AI-through-Innovation-Governance-and-Public-Trust.pdf);
  DHS's implementation in its [compliance plan](https://www.dhs.gov/sites/default/files/2025-09/25_0926_cio_dhs_compliance_plan_for_omb_m-25-21_508.pdf)).
- **NIST AI 600-1.** Minimum performance thresholds as go/no-go criteria (GV-1.3-002);
  inventory entries that name the foundation model, version, access mode, data provenance, and
  human oversight roles (GV-1.6-003); tamper-evident history of generated content and version
  control across the lifecycle (MS-2.8-003); retention of test and evaluation records (GV-1.5-003)
  ([NIST AI 600-1](https://nvlpubs.nist.gov/nistpubs/ai/NIST.AI.600-1.pdf)).
- **Practitioner consensus.** Four metrics watched together because any one moves for benign
  reasons: error rate, p95 latency, token cost per session, tool-call success rate. Evaluation is
  a separate layer from metrics. Guardrail decisions recorded on the same trace as the output they
  affected. A minimum dashboard of quality, latency, cost, and evidence completeness, where a
  missing trace is itself a defect
  ([Vercel guide](https://vercel.com/i/ai-agent-observability),
  [prompt20](https://blog.prompt20.com/posts/llm-observability-production-debugging/),
  [agent evals handbook](https://sarangk90.github.io/awesome-agent-evals-and-guardrails/03-online-evals-and-observability/04-monitoring-alerting-and-drift/)).
- **Palantir's framing**, which the panel will carry: every action traceable, every decision
  explainable; actions staged by the AI and handed to a human by default; evals suites tracked
  per LLM function; each trace tied to the data version and function version behind it; log
  access governed like data access
  ([Securing agents in production](https://blog.palantir.com/securing-agents-in-production-agentic-runtime-1-5191a0715240),
  [Connecting agents to decisions](https://blog.palantir.com/connecting-agents-to-decisions-277dee8ddb40),
  [Evals as the substrate](https://www.palantir.com/assets/xrfr7uokpv1b/4mztHRLrQU3T5CoNpX7QUH/3e1ecde0ca3344937b813e55e8ea118b/Evals_as_the_Substrate_for_Sovereign_AI.pdf)).

## The correction: which Databricks surfaces apply to our path

The unified trace table, `system.ai_gateway.usage`, the `mcpCall` audit events, and the
Govern > Traces UI are Unity Gateway surfaces ([observability](https://docs.databricks.com/aws/en/ai-gateway/observability),
[unified trace table](https://docs.databricks.com/aws/en/ai-gateway/unified-trace-table)). Our
MCP path uses the workspace endpoints, and Databricks says those "bypass Unity Gateway, so they
don't appear in its tracing tables or support MCP-level grants, policies, or guardrails"
([built-in MCPs](https://docs.databricks.com/aws/en/agents/mcp-tools/built-in-mcp-services)).
The unified trace table is also Beta behind an account-level preview and does not appear in the
GovCloud feature table at all ([mission environments](databricks-in-mission-environments.md)).

So the Databricks-side evidence for our agent is:

| Surface | What it proves | GovCloud |
|---|---|---|
| Eval results table (Delta) | per-question, per-run rows with scores, provider, latency, cost, and the AgentCore session id; the source of the AI/BI dashboard | yes |
| Unity Catalog grants on the semantic layer | the service principal can reach functions and silver views only; nothing on bronze, no write grant anywhere | yes |
| Unity Catalog lineage | bronze to silver to function to briefing table | yes |
| `system.access.audit` | who touched which securable, when | yes |
| `system.query.history` | the SQL each function and procedure ran, under which principal; corroborating evidence beside the traces | yes |
| Agent traces in a Unity Catalog trace table (day-five stretch) | every span from the deployed agent via `mlflow.strands.autolog()`, if built ([trace agents outside Databricks](https://learn.microsoft.com/en-us/azure/databricks/mlflow3/genai/tracing/prod-tracing-external)) | MLflow is in the GovCloud table |

**The identity gap and the fix (as decided 2026-10-30 evening).** With client-credentials
outbound auth, Databricks sees the service principal, not the analyst. The audit record lives in
CloudWatch, where AgentCore writes every session, model call, and tool call with arguments and
results, and in CloudTrail for Gateway policy decisions. The eval harness writes the AgentCore
session id into every results row, so a pass^3 heatmap cell links to its CloudWatch trace. The
service principal is read-only, so there is no write to attribute. The Unity Catalog trace table
in the row above is the day-five stretch, one line of code if the core is green; it is not the
audit record. An earlier version of this section had functions writing an audit table; Unity
Catalog functions cannot write ([pre-spec gaps](pre-spec-gaps.md)).

## Tier 1: must show on demo day

| Item | Artifact | Why it is minimum |
|---|---|---|
| **Quality panel** | pass^1, pass^3, question-by-run heatmap, failure categories | decided; NIST GV-1.3-002 go/no-go threshold |
| **Reliability panel** | tool error rate per tool, p95 end-to-end latency, retries, provider served per run (primary vs fallback) | the four-metric set practitioners converge on; the provider column makes the fallback decision auditable |
| **Cost panel** | tokens and dollars per question, per eval pass, prompt-cache hit rate | lens AGENTCOST; the panel will ask |
| **Evidence completeness panel** | count of runs missing a trace id, a provider, a data-file version, or a `request_context` row | "missing evidence is itself a defect"; one tile |
| **Provenance on every number** | each figure in a briefing carries the function name, the FWD file identity and version (for example `employment_202608_1`), the source row count, the model id, and the prompt version | NIST MS-2.8-003 and GV-1.6-003; the same discipline the Federal Hiring Data guide recommends for the API ([data sources](candidate-data-sources.md)) |
| **Grants** | `SHOW GRANTS` on the semantic layer: the service principal has `EXECUTE` on functions and `SELECT` on silver views, nothing on bronze | lens AGENTSEC02-BP01, enforced at the protocol layer not by the prompt |
| **Lineage** | Unity Catalog lineage graph from bronze through silver to functions and the briefing table | the Palantir "trace tied to data version" expectation |
| **One denied tool call** | a Gateway Cedar rule and a trace showing a tool call blocked by it, with the decision in CloudTrail | the only place policy outside agent code is visible; this is the planned "show a failure on purpose" |
| **Audit rows** | `system.access.audit` and `system.query.history` rows for one demo question, joined by `request_context` to the CloudWatch trace | lens AGENTSEC05 non-repudiation; answers "show me what it actually ran" |
| **Human-oversight statement** | one slide line: the agent is read-only, holds no write grant anywhere, and its recommended actions are text in a briefing the Strategic Hiring Committee reads; autonomy level "assistant" in the lens vocabulary | M-25-21 human oversight; the strongest form of Palantir's "staged by the AI, handed to a human" |
| **M-25-21 determination** | one paragraph, below | the governance artifact a DHS-adjacent panelist expects to exist |

**The determination, as written for the deck.** This use case is not high-impact under
M-25-21. Its output informs a human committee's hiring priorities and is not the principal basis
for any decision with a legal, material, binding, or significant effect on an individual's rights
or safety; no individual-level data is processed. It would still be entered in the agency's AI
use case inventory with the foundation model, version, access mode, data sources, and oversight
role named, per NIST GV-1.6-003. Pre-deployment testing exists in the form of the golden set and
the pass^3 threshold, and ongoing monitoring reuses the same scorers on production traces, so if
an agency later classified it as high-impact the minimum practices would already have evidence
behind them.

## Palantir vocabulary table

| Panel will say | We show |
|---|---|
| Action Log | not applicable: the agent performs no actions; CloudWatch holds every tool call it made |
| Evals suite tracked per function | pass^3 by question, function name on every graded number |
| Trace tied to data version and function version | FWD file identity, function name, prompt version on every row |
| Markings and granular policies | Unity Catalog grants on the service principal; Cedar rule at the Gateway |
| Staged by the AI, released by a human | the briefing proposes, the committee decides; the agent cannot write, so nothing can close the loop automatically |

## Tier 2: log it, do not show it

- AgentCore built-in session metrics and CloudWatch GenAI Observability (invocations, tokens,
  latency, errors by agent). Present by default once ADOT instrumentation is on; open it only if
  asked "how would you run this without Databricks"
  ([AgentCore observability](https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/observability-telemetry.html)).
- Full per-span traces in CloudWatch Transaction Search. Keep one bookmarked for the denied-call
  demo.
- CloudTrail data events on the Gateway. Retain for the week; show only the one denial.
- Prompt and tool-schema versions in git with the commit hash on each trace. "Agent behavior as
  code" per the lens; mention, do not demo.
- Data-quality step results from the Lakeflow job (row counts, version changes, coverage gaps
  such as the Department of War June and July 2026 files). Feeds the evidence panel; the detail
  stays in a table.

## Tier 3: skipped, with the reason

| Item | Why not |
|---|---|
| Unity Gateway service policies, guardrails, unified trace table, `system.ai_gateway.usage` | not on our MCP path, Beta behind an account preview, and absent from the GovCloud feature table |
| Inference tables | per model-serving endpoint; we serve no model on Databricks |
| Bedrock Guardrails | the model is called through vendor APIs, and AgentCore in GovCloud lists "Bedrock Guardrails Policy is not available" ([GovCloud doc](https://docs.aws.amazon.com/govcloud-us/latest/UserGuide/govcloud-bedrock-agentcore.html)) |
| AgentCore Memory | no state to remember across sessions in a scheduled briefing |
| Drift detection, prompt-injection monitoring, PII redaction rates | public data, one trusted user class, no PII in scope; name the limit in one sentence rather than build a panel for it |
| On-behalf-of identity to Databricks | deferred in the MCP-path decision; the correlation id covers the audit need for the demo |
| A real DHS inventory submission | a sentence in the deck, not a build |

## What this changes on other pages

- The [MCP-path decision](../../DECISIONS.md) gains a build-week item: the `request_context`
  parameter on every Unity Catalog function and the `agent_calls` audit table.
- The [agent-evaluation concept](../concepts/agent-evaluation.md) dashboard gains the
  reliability, cost, and evidence-completeness panels beside the quality panel.
- The "show a failure on purpose" moment from the [playbook](fde-build-challenge-playbook.md)
  now has a candidate: the denied tool call.

## Not verified

- Whether a Unity Catalog function called through the MCP functions endpoint under a service
  principal appears in `system.query.history` and `system.access.audit`, and whether the Genie
  Agent endpoint records its generated SQL there.
- Whether AgentCore traces can also be exported to a Databricks MLflow trace table (dual export).
  Not needed if the correlation id works.
- Unified trace table availability in GovCloud; it is absent from the feature table, which is
  not the same as listed unavailable.
