# Should an analytics agent get a freeform SQL tool in a mission environment?

**Question (Ryan, 2026-10-31):** research the pattern for analytics agents querying data. Is a
freeform SQL tool a good idea in mission environments like this one?

**Answer in one line:** no. Production teams, benchmarks, security guidance, Databricks, and
Palantir converge on the same shape: fixed, governed query logic for every number that matters,
a bounded natural-language path for exploration, and no open-ended SQL tool. That is the design
in [spec 03](../../challenge/specs/03-semantic-layer.md); nothing changes, three things sharpen.

## What production teams did

| Team | Pattern | Stated reason |
|---|---|---|
| Block (2026-04) | Split one MCP into two: a governed metrics tool that runs pre-approved SQL the LLM "cannot edit" and never sees, and a separate exploratory text-to-SQL tool with a human-reviewed report before execution | "100% metric accuracy for governed metrics with no SQL review required"; one combined tool satisfied nobody ([Block Engineering](https://engineering.block.xyz/blog/building-the-data-foundation-for-automated-analytics)) |
| AWS finance via dbt (2026-10) | Agent selects from an enumerated list of certified metrics; MetricFlow compiles the SQL; the Redshift MCP enforces read-only single statements at three layers (server, IAM, database grants). Every answer carries metric name, compiled SQL, source model, test results, and a query id | A revenue query was $3.5 million wrong; fabricated metrics became "structurally impossible under this design, not just discouraged by a prompt" ([dbt Labs](https://www.getdbt.com/blog/aws-dbt-semantic-layer-ai-agent-revenue-accuracy)) |
| Pinterest (2026-03) | Kept SQL generation, fenced: verified historical queries, metric definitions, governance-aware table ranking, EXPLAIN before execute, tight LIMITs | Business-logic correctness, not syntax, is the failure mode ([Pinterest Engineering](https://medium.com/pinterest-engineering/unified-context-intent-embeddings-for-scalable-text-to-sql-793635e60aac)) |
| Rohlik (2026-04) | Verified queries and approved metric formulas searched first; read-only by default; every query validated to start with a read keyword | "Close" in a finance report is wrong ([Rohlik](https://blog.rohlik.group/blog/ai-analytics-semantic-layer)) |
| Datalane (2026-05) | Model emits a JSON query spec against a semantic layer; a deterministic compiler writes SQL; unsupported requests refuse rather than improvise. Freeform kept behind a flag for about 8% of questions, labeled unverified | "The model chooses. The compiler writes." ([Datalane](https://www.datalane-data.blog/blog/text-to-sql-in-production/)) |
| AngelList (2026-08), the dissent | Agent writes SQL from markdown knowledge files; no planner | Accepts the trade: a planner query "is guaranteed to use the canonical definition, and ours is only very likely to" ([AngelList](https://www.angellist.com/blog/the-semantic-layer-nobody-maintains)) |

## Why freeform fails on realistic schemas

Spider 1.0 scores above 85% made text-to-SQL look solved. Enterprise-shaped benchmarks reverse
that. Spider 2.0 (632 tasks over schemas averaging 812 columns): the best agent framework solved
21.3% at publication, traditional text-to-SQL parsers under 6% ([ICLR 2025](https://arxiv.org/html/2411.07763v2)).
BIRD-Ent and Spider-Ent: drops of up to 35 points as schema width grows, best models at 39.1% and
60.5% ([EMNLP 2026](https://aclanthology.org/2026.findings-emnlp.1971.pdf)). BEAVER, from real
enterprise query logs: off-the-shelf LLMs answered none correctly ([MIT, 2025](https://arxiv.org/html/2409.02038v2)).
The OPM employment table has 65 columns with a coded and a text twin for most fields, the shape
these benchmarks punish. Quote the figures as "at publication"; newer models may have moved them.

## Why it fails in a mission environment specifically

- **OWASP Excessive Agency** names the controls: "avoid open-ended tools", enforce permissions
  "by applying appropriate database permissions for the identity", and "implement authorization in
  logic rather than relying on an LLM to decide if an action is allowed" (complete mediation). The
  2026 prompt-injection entry adds that NIST AI 100-2 and the CISA joint guidance frame deterministic
  mediation of privileged calls as "a baseline procurement expectation"
  ([OWASP LLM Top 10 2026](https://genai.owasp.org/download/56857/)).
- **Google's MCP security guidance** gives the exact failure: an `execute_sql` tool lets a user
  trick the agent into reading data the agent can see but the user should not. "Instructing the
  agent to enforce the access rules is typically not sufficient." The fix is a specific tool "where
  the identity of the user in the query filter is set outside of the agent's control"
  ([Cloud SQL docs](https://docs.cloud.google.com/sql/docs/sqlserver/secure-agent-interactions-mcp)).
- **Database content is an injection vector.** Query results entering the context can carry
  instructions, so a freeform tool turns every readable row into attack surface
  ([MCP Toolbox advisory](https://github.com/googleapis/mcp-toolbox/issues/2844)). USAJOBS posting
  text in `silver.job_postings` is third-party content of exactly this kind.
- **Palantir**, whose stack the Firm's clients run, bounds agents to Ontology functions and Action
  types with permissions that "explicitly dictate the set of allowable operations", enforced at the
  infrastructure layer; agents "should only be authorized to take actions within a scoped environment"
  ([Agentic Governance white paper](https://assets.ctfassets.net/xrfr7uokpv1b/5mrqbUZiSS4sqXwJYIGlkt/8b5288fb15bd175a694c700a49c330db/Agentic_Governance_White_Paper.pdf);
  [Connecting agents to decisions](https://blog.palantir.com/connecting-agents-to-decisions-277dee8ddb40)).
  A freeform SQL tool has no analogue in that model.

## What Databricks itself recommends

The tool-selection table is a ranking. Unity Catalog function tools: "run a predefined query with
parameters". Genie: natural-language questions, "more accurate answers than an agent writing SQL
directly against raw tables". The Databricks SQL MCP: "developer queries and data engineering",
such as "validating syntax or authoring a pipeline"
([structured retrieval tools](https://docs.databricks.com/aws/en/agents/custom-agents/structured-retrieval-tools);
[Databricks-provided MCPs](https://docs.databricks.com/aws/en/agents/mcp-tools/built-in-mcp-services)).
Genie's trusted assets are Block's pattern inside Genie: table-valued functions Genie "cannot view
or modify", "well-suited for logic that should not be surfaced or changed"
([tune Genie quality](https://docs.databricks.com/aws/en/genie-agents/tune-quality)).

Two governance notes from the same pages. The Genie Agent endpoint (`/api/2.0/mcp/genie/{id}`)
bypasses Unity Gateway, so MCP-level grants, policies, and tracing do not apply to it; access rests
on permissions on the space and its data. And the `system.ai` MCPs that do carry Unity Gateway
governance are the ones the GovCloud research found outside the FedRAMP High boundary
([mission environments](databricks-in-mission-environments.md)).

## What it means for the build

The design holds: fixed-SQL functions for every graded number, the Genie Agent for bounded
exploration where Genie writes the SQL under Unity Catalog permissions, no freeform tool. Three
sharpenings for the deep dive:

1. **Name the tiers, and the refusal.** The service principal's OAuth secret carries the
   `unity-catalog` and `genie` scopes only, so the Databricks SQL MCP (`sql` scope) is refused at
   the token, before any policy. Say that out loud.
2. **Register the eight functions as Genie trusted assets** (spec 03, step 6). Genie's answers to
   the eight question families then come back verified, and the exploratory path reuses the graded
   path instead of competing with it.
3. **State the Genie caveat.** Genie Agent calls bypass Unity Gateway; the policy layer in this
   architecture is AgentCore Gateway (Cedar rule, CloudTrail), which is also the published
   public-sector pattern. Both facts belong in the same sentence.

The one case for a freeform tool is the one Block kept: a technical analyst exploring with the SQL
shown and a human approving before execution. That is a different user from the CHCO briefing and
would be a separate agent with a separate identity if it were ever added.

## Not checked

Full text of the Spider 2.0 and dbt pages (search excerpts only); the current Spider 2.0
leaderboard for 2026 models; whether Databricks has published accuracy numbers for Genie trusted
assets versus freeform Genie.
