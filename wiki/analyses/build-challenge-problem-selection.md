# Build challenge: is federal workforce planning the right problem?

**Question (Ryan, 2026-10-30):** Yesterday's Grok session narrowed the build challenge to
workforce management, because the Firm has an FDE posting in that domain. Hard constraint: build
on Databricks, since the first technical screen asked "can Ryan pick up Databricks fast?" Is this
the right problem set?

**Answer: yes, with a sharper framing.** Build a *federal workforce-risk briefing agent* for an
agency Chief Human Capital Officer, on Databricks on AWS, fed by OPM's new open workforce API. It
is the only candidate that scores high on every criterion the challenge email sets, and it has the
best public data of any option. See [Platform decision](#platform-decision-databricks-on-aws-paid-torn-down-after)
and [Risks](#risks-to-retire-on-day-one). Source: [build challenge email](../sources/build-challenge-email.md).

## What the challenge actually asks for

From the challenge email (`raw/2026-10-29-build-challenge-email.md`): an agentic system using
Claude, Gemini, or GPT, not production-ready, with "sufficient complexity (e.g.: orchestration of
multiple agents, setting up an MCP Server and/or Client, accessing data via APIs, building skills,
etc)." The 15-minute pitch must cover problem choice, users, expected impact, technical choices,
architecture, and LLM usage; mostly live demo, code walkthrough, and architecture review. Then 30
minutes of deep-dive questions. Due EOD 2026-11-05.

Rubric used below:

| # | Criterion | Source |
|---|---|---|
| R1 | Naturally needs multi-agent orchestration | email |
| R2 | Naturally needs an MCP server or client | email |
| R3 | Pulls real data from live APIs | email |
| R4 | Has a place for skills | email |
| R5 | Named user and credible impact story | email (15-min pitch) |
| R6 | Survives a live demo and a 30-minute deep dive | email |
| R7 | Databricks is load-bearing, not decorative | Ryan's constraint |
| R8 | Buildable in under a week by one person | deadline |
| R9 | Matches what the Firm's federal FDE program actually sells | research below |

## What the research changed

1. **The workforce-planning posting is a Palantir role, not a Databricks one.** It sits in the
   Firm's Decision Analytics unit and asks for Foundry, AIP, Ontology, and Workshop
   (`raw/2026-10-30-firm-palantir-workforce-posting.md`). So "there is a posting" is a weaker
   signal than Grok implied. The domain is still real demand at the Firm, but Databricks is Ryan's
   choice, not the posting's.
2. **The FDE program does have a Databricks track.** A "Forward Deployed Data Engineer -
   Databricks" posting in the same department as Ryan's role asks for Databricks Apps (front and
   back end), Spark pipelines, Unity Catalog governance, and LLM integration with OpenAI, Anthropic,
   or Gemini (`raw/2026-10-30-firm-fde-databricks-posting.md`). That is a checklist for the build.
3. **The Firm's federal Databricks wins are "executive insight in days" stories.** The joint
   point-of-view paper with Databricks cites a cabinet-level leader "overseeing 200,000+
   employees" who needed "rapid, defensible insight across fragmented systems" before
   congressional testimony, and a Monday-kickoff-to-Friday-demo federated analytics build
   (`raw/2026-10-30-firm-databricks-federal-evidence.md`). A workforce briefing agent is the same
   shape of story.
4. **The role Ryan interviewed for is platform-agnostic and frontier-lab-first.** The program
   partners with Palantir, Databricks, OpenAI, Anthropic, Google, Snowflake, and NVIDIA; the posting
   stresses agentic orchestration, RAG, ontology modeling, and schema-tolerant ingestion
   (`raw/2026-10-30-firm-fde-ai-engineer-posting.md`). The program's public partnerships and its
   student build-challenge event lean Palantir
   (`raw/2026-10-30-firm-databricks-federal-evidence.md`), so expect ontology-flavored questions in
   the deep dive.
5. **The public data is far better than expected.** OPM replaced FedScope with the Federal
   Workforce Data site in 2026. It publishes record-level monthly Employment, Accessions, and
   Separations files as Parquet through an unauthenticated REST API
   ([API Access](https://data.opm.gov/get-data/api-access)). Employment is 2M+ rows per month with
   agency, sub-agency, occupation series, pay plan, grade, salary, duty-station state, age bracket,
   education, length of service, supervisory status, appointment type, work schedule, and STEM flag
   ([data dictionary excerpt](https://www.opm.gov/data/datasets/Files/759/949b3125-11c9-4ef5-b95e-498b96791574.pdf)).
   The September 2026 release lands **2026-11-04**, the day before the deadline
   ([Data Sources](https://data.opm.gov/resources/data-sources)). The
   [USAJOBS Search API](https://developer.usajobs.gov/api-reference/get-api-search) adds the demand
   side (open postings by agency, series, grade, location) with a free key.
6. **The problem is topical and quantified.** GAO reports nearly 378,000 separations and about
   127,000 hires across 22 major agencies in 2025, a net decline of roughly 11%, with 18 of 22
   agencies down more than 10% ([GAO-26-108583](https://www.gao.gov/products/gao-26-108583)). At
   OPM itself, 57% of leavers had 11+ years of service and skills gaps have been on GAO's High-Risk
   List since 2001 ([GAO-26-108916](https://www.gao.gov/products/gao-26-108916)). OPM's FY2026-28
   recruitment plan tells agencies to "align recruitment strategies with validated workforce
   planning data to target mission-critical skill gaps"
   ([OPM memo](https://www.opm.gov/chcoc/latest-memos/fy-2026-28-government-wide-recruitment-strategic-plan.pdf)).
   GAO did its own analysis directly from the same FWD files, which validates the data choice.

## Alternatives considered

| Candidate | Data | R9 fit | Why not (or why backup) |
|---|---|---|---|
| **A. Federal workforce-risk briefing agent** | OPM FWD (no auth, Parquet, monthly) + USAJOBS (free key) | Palantir workforce posting; Google-partnership HR agents; "200,000 employees" POV anecdote | **Recommended.** |
| B. Agency spending / financial intelligence | [USAspending API v2](https://api.usaspending.gov/docs/endpoints), no key | Palantir partnership offering "Operationalize Financial Intelligence" | Strong backup. Same architecture, swap the data. Less urgent story than the 2025 workforce shock. |
| C. Cyber risk fusion | CISA KEV, NVD (not re-verified this session) | The Firm already sells Dark Light on Databricks | Looks derivative of an existing accelerator; harder to show a non-expert panel the impact. |
| D. Critical-minerals supply chain | Thin public data | DOE Genesis Mission work with Databricks Federal | Mission-aligned but no clean API; not buildable in a week. |

Scores (3 = strong, 1 = weak):

| | R1 agents | R2 MCP | R3 APIs | R4 skills | R5 user/impact | R6 demo | R7 Databricks | R8 week | R9 Firm fit | Total |
|---|---|---|---|---|---|---|---|---|---|---|
| A workforce | 3 | 3 | 3 | 3 | 3 | 2 | 3 | 2 | 3 | 25 |
| B spending | 3 | 3 | 3 | 3 | 2 | 2 | 3 | 2 | 2 | 23 |
| C cyber | 2 | 3 | 2 | 2 | 2 | 2 | 3 | 2 | 2 | 20 |
| D minerals | 2 | 2 | 1 | 2 | 3 | 1 | 2 | 1 | 3 | 17 |

A and B score 2 on R6 and R8 because both carry the same platform-setup risk in week one (see
[Risks](#risks-to-retire-on-day-one)); the ranking does not move. A wins on the impact story (GAO
numbers, a posting at the Firm in the exact domain) and on how directly Databricks' own federal
case studies rhyme with it.

## Recommended framing

- **User:** an agency Chief Human Capital Officer or workforce-planning analyst preparing a
  staffing plan or a hearing briefing.
- **Decision:** where are attrition-driven capability gaps forming (sub-agency x occupation x
  location x tenure band), and are open USAJOBS postings actually aimed at them?
- **Impact:** replaces weeks of spreadsheet work against 2M-row files with a governed,
  reproducible briefing; the OPM memo above makes this a stated federal requirement.
- **Demo moment:** build and rehearse on the August 2026 files already published. If OPM's
  September release lands on schedule on 2026-11-04, ingest it live and have the agent explain
  what changed; OPM notes that files sometimes arrive late, so treat this as a bonus, not a
  dependency.

## Minimal Databricks surface that checks every box

| Email criterion | Databricks component | Why it is necessary, not decorative |
|---|---|---|
| Data via APIs (R3) | Ingestion job pulls OPM Parquet + USAJOBS JSON into a Unity Catalog volume, then bronze/silver Delta tables (Lakeflow pipeline or notebook job) | The posting asks for schema-tolerant ingestion; OPM versions its files, so re-ingest logic is real. |
| MCP server (R2) | Databricks managed MCP: Genie Agent over the silver tables, plus Unity Catalog functions (e.g. attrition rate, vacancy match) exposed as tools ([Databricks-provided MCPs](https://docs.databricks.com/aws/en/agents/mcp-tools/built-in-mcp-services)) | The agent's data access is governed by Unity Catalog permissions, which is the Firm's standard deep-dive answer. |
| MCP client (R2) | The agent app consumes those MCP servers; Claude Code can also attach to them for the code walkthrough ([Connect Claude Code](https://docs.databricks.com/aws/en/ai-gateway/coding-agent-claude)) | Shows both sides of MCP. |
| LLM of choice | Claude via Foundation Model API pay-per-token endpoints such as `databricks-claude-sonnet-5-5` ([supported models](https://docs.databricks.com/aws/en/machine-learning/foundation-model-apis/supported-models)) | Claude runs natively inside Databricks under the same auth and governance; answers "picked up Databricks" and "uses Claude" in one line. |
| Multi-agent orchestration (R1) | Supervisor agent with three workers: data-quality/ingest checker, workforce analyst (Genie + UC functions), hiring-market analyst (USAJOBS), plus a briefing writer. Deployed as a Databricks App ([Agent Bricks platform](https://www.databricks.com/blog/agent-bricks-governed-enterprise-agent-platform)) | Each worker has a different tool set and data source, so the split is justified rather than theatrical. See [multi-agent orchestration](../concepts/multi-agent-orchestration.md). |
| Skills (R4) | Claude skills for the briefing format and for OPM code-list lookups; Unity Catalog Skills are in Beta per the platform release notes | Cheap to add, and the email names them. |
| Deep dive (R6) | MLflow tracing on every tool call | Lets Ryan show exactly which agent called which tool with which SQL. |

Palantir translation for the deep dive: Unity Catalog + Genie's semantic layer is the Databricks
answer to Foundry Ontology; UC functions are the answer to AIP Logic; Databricks Apps are the
answer to Workshop.

## Platform decision: Databricks on AWS, paid, torn down after

Ryan's soft requirement (2026-10-30) is that everything runs on real infrastructure, so the build
targets a Databricks workspace on AWS, pay-as-you-go, with a budget under $50 for the week and
teardown after the interview. This retires the Free Edition risks that would otherwise threaten
R6 and R8:

- **Egress.** A standard workspace defaults to full outbound access
  ([serverless egress control](https://docs.databricks.com/aws/en/security/network/serverless-network-security/network-policies)),
  so jobs can call `data.opm.gov` and `data.usajobs.gov` directly. Free Edition restricts egress
  to an unpublished allowlist
  ([limitations](https://docs.databricks.com/aws/en/getting-started/free-edition-limitations)).
- **Previews and models.** A full account has the account console, so the Unity Gateway beta and
  the `system.ai` MCPs can be enabled, and all Claude pay-per-token endpoints are available.
- **Trial first.** Sign up with the business email: the trial doc says personal-email trials get
  "limited external network access" and capped compute, while business-email trials avoid those
  limits ([free trial](https://docs.databricks.com/aws/en/getting-started/free-trial)). Trial
  credits cover Databricks DBUs; AWS infrastructure (S3, any classic compute) bills separately.

Cost levers to stay under $50: serverless only (no classic clusters), one 2X-Small SQL warehouse
with a short auto-stop, jobs triggered on demand rather than scheduled, Apps stopped between
rehearsals, a Databricks budget alert (Budgets are GA per the platform release notes), and an AWS
budget alert on the account. Delete the workspace and the S3 bucket after the interview.

## Risks to retire on day one

1. **Account and preview enablement.** Confirm serverless, Databricks Apps, Managed MCP Servers,
   and the Claude endpoints are all available in the chosen AWS region before writing code. If a
   preview is region-gated, pick `us-east-1` or `us-west-2`.
2. **Spend.** Confirm the trial credits are active and set both budget alerts in the first hour.
   The main cost risk is a serving endpoint or App left running overnight.
3. **Fallback.** Free Edition remains the zero-cost fallback. Its constraints are: 3 Apps, 1
   SQL warehouse (2X-Small), 5 concurrent job tasks, apps auto-stop after 24 hours, restricted
   egress, "certain models not available". If it is ever needed, run the OPM and USAJOBS fetch
   outside Databricks and push Parquet to the Unity Catalog volume with the Files API.

## Not verified this session

- The Grok notes and the posting text Ryan saw are not in `raw/`; this analysis found the
  postings independently. Drop the Grok transcript into `raw/` if it has anything else.
- CISA KEV and NVD access terms for option C were not re-checked.
- Whether USAJOBS API keys are issued instantly (historically they arrive by email within minutes).
- Exact Free Edition behavior for the two risks above.

## Sources not yet ingested as wiki source pages

The raw files listed above and the challenge email are cited directly. Proper `wiki/sources/`
pages, plus entity pages for the Firm's federal FDE program, OPM Federal Workforce Data, and
Databricks managed MCP, are the next wiki step once Ryan confirms the direction.
