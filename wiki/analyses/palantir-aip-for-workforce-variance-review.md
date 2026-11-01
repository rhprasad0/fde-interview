# How the quarterly variance review would be built on Palantir AIP, and what that means for the build

**Question (Ryan, 2026-11-01):** I am reconsidering the freeform analyst chatbot; it overlaps
heavily with OPM's FWD Chat. How could our user and problem benefit from Palantir AIP? Record that
I tried to sign up for AIP and could not. Keep a Palantir knock-off theme, since the Firm uses
Palantir as its federal AI platform.

**Answer in one line:** Palantir ships two different things for two different jobs. AIP Analyst
is an agentic chat over the Ontology for ad-hoc questions, and FWD Chat and Genie are the same
shape. Workshop is an operational app where a scoped agent drafts a decision, a human approves
it, and the decision is captured. The CHCO's quarterly variance review is a Workshop-shaped
problem, so the knock-off to build is the app, with the chat demoted to a scoped follow-up
assistant inside it.

## AIP Developer Tier: attempted 2026-11-01, unavailable

Ryan tried to create an AIP Developer Tier account on 2026-11-01 and could not. Palantir paused
online signups on 2026-10-23 "while working on some exciting enhancements and updates"; a waitlist
is open and existing accounts keep working
([community announcement](https://community.palantir.com/t/a-quick-update-on-aip-developer-tier/7404)).
The tier was free with capacity limits "baked in"
([billing thread](https://community.palantir.com/t/developer-tier-billing-and-usage/1074)).
So the precise statement for the panel is "signups paused since 2026-10-23, waitlist joined,
not available during the build week," not "discontinued." The agent-layer decision had already
rejected the tier for a different reason (two unfamiliar platforms in one week); this makes the
rejection moot ([DECISIONS.md](../../DECISIONS.md), Agent layer).

## Why the Firm's stack matters here

On 2025-06-30 the Firm's federal subsidiary became a Palantir preferred implementation partner
for U.S. federal customers, with 1,000 Data & AI staff to be trained and certified on Foundry
and AIP. The three initial joint offerings are data fusion to the tactical edge, supply chain
orchestration, and financial intelligence; none is workforce planning
(`raw/2026-11-01-firm-palantir-partnership.md`). The workforce-planning Palantir FDE posting in
the Firm's Decision Analytics unit asks for "Ontologies, Workshop applications, AI workflows,
scenario analysis, and explainable recommendations"
(`raw/2026-10-30-firm-palantir-workforce-posting.md`). That phrase is the shape the panel will
expect, and it is not a chatbot.

## Two Palantir surfaces, two jobs

| Surface | What it is | Our analogue | Who it serves |
|---|---|---|---|
| **AIP Analyst** (GA week of 2026-04-13) | Agentic natural language over the Ontology: object type search, object sets, Ontology SQL, aggregations, Vega charts, maps; shows a dependency graph and inline citations; may ask clarifying questions ([overview](https://palantir.com/docs/foundry/aip-analyst/overview/), [capabilities](https://palantir.com/docs/foundry/aip-analyst/capabilities/), [announcement](https://palantir.com/docs/foundry/announcements/2026-03/)) | Genie, and OPM's FWD Chat over the same public data ([data.opm.gov](https://data.opm.gov/)) | A person exploring |
| **Workshop app with an embedded AIP Agent** | Operational application; the agent takes the app's state (a filtered object set) as context, drafts proposals, and calls permissioned Actions; a human approves ([platform overview](https://palantir.com/docs/foundry/platform-overview/overview/), [embedding agents](https://build.palantir.com/platform/e255d989-9b1e-4322-b496-f94844894a12), [retrieval context](https://palantir.com/docs/foundry/chatbot-studio/retrieval-context/)) | What spec 04 should build | A person deciding |

Palantir's own Analyst docs note that "a single question can result in many model calls and many
queries" and give guidance on "when to move work out of the agent's tool loop" (the rest of the
sentence was not read) ([overview](https://palantir.com/docs/foundry/aip-analyst/overview/)).
That is the same argument the freeform-SQL analysis made for fixed functions
([freeform SQL vs governed tools](freeform-sql-vs-governed-tools.md)).

The FWD Chat test, answered: FWD Chat is an Analyst-shaped tool over one source with no staffing
plan, no postings, no decision capture, and no schedule. A chatbot over our semantic layer
would differ only in the join. A variance-review app differs in kind.

## Palantir's decision model, mapped onto the build

Palantir models a decision as data, logic, actions, and security, and says the Ontology
"represents the decisions in an enterprise, not simply the data"
([why an Ontology](https://palantir.com/docs/foundry/ontology/why-ontology/)). "In most patterns,
rather than directly make changes, AI agents create proposals ... surfaced to an operator for
refinement, feedback, and a resulting decision"
([platform overview](https://palantir.com/docs/foundry/platform-overview/overview/)).

| Palantir primitive | What it does there | In this build | Status |
|---|---|---|---|
| Ontology object types and links | Agency, position, person, posting as governed objects | The eight `semantic` views and the Genie space over Unity Catalog ([spec 03](../../challenge/specs/03-semantic-layer.md)) | Built |
| AIP Logic function | Typed inputs, deterministic blocks plus a Use LLM block, typed output; unit tests and AIP Evals attached ([Logic getting started](https://palantir.com/docs/foundry/logic/getting-started/)) | The agent as a **briefing function**: input (component, occupation, quarter), fixed calls to the UC functions, one LLM narrative step, output a variance brief with provenance | Spec 04 |
| Actions, proposal-based | Permissioned "verbs"; the agent stages, a human approves; the Andersen workforce app on Foundry used "Propose Reallocation" and "Commit Assignment" ([Andersen case](https://global.andersen.com/consulting/optimizing-workforce-allocation-case-study)) | Recommendations in the brief that the analyst accepts, rejects, or flags for the Strategic Hiring Committee | Collides with read-only; see below |
| Scenario | A fork of the Ontology made by applying Actions; example uses include "personnel scheduling" and "resource allocation" ([what-if example](https://build.palantir.com/platform/596fb429-6d17-48de-b70c-6a520fb4eab2)) | What-if on the synthetic staffing plan: "if TSA fills 200 of the 1802 postings by Q2, the variance closes to X" | Stretch |
| Automate | Conditions monitored continuously, triggering Actions or Logic runs ([write-back example](https://build.palantir.com/platform/e28c95c8-24d7-4b39-afd3-a9ad25449894)) | The Lakeflow job: monthly ingest, refresh, scheduled briefs, threshold alerts | Decided |
| AIP Evals | Generated test cases and evaluators on a Logic function | The pass^3 harness and dashboard ([agent evaluation](../concepts/agent-evaluation.md)) | Spec 05 |
| AIP Analyst | Ad-hoc agentic exploration | Genie as the exploratory tier, labeled and measured ([Genie accuracy](genie-accuracy.md)) | Measured in spec 05 |
| Workshop module with embedded agent | The operational UI; agent scoped by application state | The variance-review app: one brief per component x occupation cell, a follow-up assistant scoped to the open cell | Spec 04 |

### Federal precedent for the app shape

The Army's MOS Health Dashboard (launched 2025-12-08) runs on Army Vantage, Palantir's platform,
over IPPS-A personnel data and tracks accessions, retention, on-hand versus authorized strength,
and attrition by specialty so leaders can "shift from reactive personnel management to proactive
readiness shaping" ([army.mil](https://www.army.mil/article/289432/)). Vantage began in 2018
"with an initial focus on understanding personnel readiness"
([Palantir](https://www.palantir.com/army-vantage/)). Strength versus authorized by specialty is
the military form of onboard versus plan by occupation. It is a dashboard with workflows, not a
chat box.

On the civilian side, OPM awarded the governmentwide core HR platform in June 2026 (the vendor
is not named in OPM's post) with "a single source of truth for workforce information" as the
goal ([OPM](https://www.opm.gov/news/secrets-of-opm/from-vision-to-reality/)). In deployment the
staffing plan and position data would come from that system; the synthetic plan stands in for it.

## Where the knock-off collides with a logged decision

Palantir's pattern ends in a write: proposal, human approval, Ontology edit. This build is
read-only. The agent holds no write grant anywhere and the Lakeflow job owns every write
([DECISIONS.md](../../DECISIONS.md), Domain model correction). Decision capture needs something
to write. Three options, not chosen here:

1. **The app writes under its own identity.** A separate service principal with `INSERT` on one
   `decisions` table; the agent identity stays read-only. Closest to Palantir's model, where the
   Action's permission belongs to the user, not the agent.
2. **The job materializes decisions** from an app-owned table on its schedule. Same boundary,
   fewer moving parts at demo time, but decisions appear with a lag.
3. **Capture stays out of scope.** Recommendations live in the brief text for the committee, as
   decided on 2026-10-30. Defensible as "autonomy level: assistant," but the panel will ask where
   the decision goes.

For today's user test, an accept, reject, or flag control that writes nowhere is fine if the
tester is told so, and what they click is itself data about which recommendations they trust.

## Recommendation for Ryan to confirm

Build spec 04 as a variance-review app, not an analyst chatbot: a list of component x occupation
cells for the quarter ranked by variance to plan, each opening to a brief produced by the
briefing function with every number traced to a function call and every imputed or synthetic
value labeled, a recommendation block with accept, reject, or flag, and a follow-up assistant
scoped to the open cell that routes to the eight functions first and Genie second. UI copy in HR
vocabulary only (staffing plan, variance, separations, mission-critical occupations). The AIP
mapping above is for the panel, not the screen. Choose a decision-capture option before the spec
is written.

## Not checked

Full text of the Andersen case study (search excerpt only) and of AIP Analyst's "move work out
of the tool loop" guidance (truncated). Palantir's documentation pages carry evergreen URLs with
2021 publish dates and are cited as current docs. Whether the Developer Tier waitlist has
reopened since 2026-10-23. The Core HCM award vendor.
