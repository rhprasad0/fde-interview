# Gaps to close before writing the spec

**Question (Ryan, 2026-10-30):** Are there critical gaps in the research to fill before we begin
writing the spec?

**Answer in one line:** two logged designs did not work as written. Ryan resolved both the same
evening by removing the need: the agent is read-only, so there is no write path to design, and
the audit record is CloudWatch, so there is no trace table to build. MLflow moved from dependency
to day-five stretch. What remains is a short day-one verification list and two logistics
questions. Nothing blocks the spec.

**Resolution (2026-10-30 evening, logged in `DECISIONS.md`).** Gap 1: write-backs dropped;
recommended actions live in the briefing text. Gap 2: CloudWatch and CloudTrail are the audit
record; Databricks shows governance through grants, lineage, query history, and the results
table. Gap 3: a plain Python harness in a Databricks notebook writes results to Delta; MLflow
wraps it on day five if the core is green. The sections below are kept as the research record
and as the fallback designs if a panelist asks "what if the agent needed to write."

## Gap 1: Unity Catalog functions cannot write

**What was assumed.** The domain-model decision said write-backs (flag a gap, stage a briefing
item) would be Unity Catalog functions playing the role of Palantir Actions. The observability
page added a `request_context` parameter that every function would write to an `agent_calls`
audit table.

**What the docs say.** Unity Catalog Python UDFs "run in a secure, isolated environment and do not
have access to file systems or internal services" and "must return a scalar value"
([UDFs in Unity Catalog](https://learn.microsoft.com/en-us/azure/databricks/udf/unity-catalog)).
There is "no supported method" for a UC Python UDF to reach Spark or run SQL
([Databricks community, staff answer](https://community.databricks.com/t5/data-engineering/how-can-i-execute-a-spark-sql-query-inside-a-unity-catalog/td-p/121784)).
SQL functions return a value or a table and "cannot include dynamic SQL or procedural logic"
([stored procedures blog](https://www.databricks.com/blog/introducing-sql-stored-procedures-databricks)).
Databricks recommends UC functions as tools "specifically for structured data retrieval tools
when the query is known ahead of time"
([create agent tools](https://learn.microsoft.com/en-us/azure/databricks/generative-ai/agent-framework/create-custom-tool)).
Reads are fine. Writes are not possible.

**The fix: SQL stored procedures.** Generally available since 2025-08, Unity Catalog governed,
`CREATE PROCEDURE ... SQL SECURITY DEFINER` runs the body "under the authority of the owner
(definer) of the procedure, regardless of which user invokes the procedure. The invoker only
requires the `EXECUTE` privilege" ([CREATE PROCEDURE](https://docs.databricks.com/aws/en/sql/language-manual/sql-ref-syntax-ddl-create-procedure)).
So the service principal gets `EXECUTE` on `stage_briefing_item` and never gets `INSERT` on the
table. The procedure writes the staged item and its own audit row carrying the request context.
This is a closer Palantir Action analog than a function was: a named, governed, parameterized
write with its own log.

**The decision Ryan owns: how the agent invokes `CALL`.**

| Path | Cost | Trade |
|---|---|---|
| Point the MCP functions server at the procedure name | five-minute test | procedures and functions share the routine namespace, so it may just work; undocumented |
| Lambda target on AgentCore Gateway with a fixed tool signature, calling the Statement Execution API with a parameterized `CALL` and `query_tags` ([execute statement](https://docs.databricks.com/api/statement-execution/v1/execute-statement.md)) | half a day | fixed tool surface, which the pass^3 bar favors; tags land in `system.query.history` |
| Databricks SQL MCP server `/api/2.0/mcp/sql` ("read and write") | zero code | hands the model arbitrary SQL, which is variance the eval does not want |

Lean: test the first on day one, build the second, keep the third as fallback. Verify `CALL`
through the Statement Execution API; the only restriction found is inside interactive JDBC
transactions, a different context ([transaction modes](https://docs.databricks.com/aws/en/transactions/transaction-modes)).

## Gap 2: the audit design depended on gap 1

**What replaces it.** The read path is fully recorded without any function writing anything: the
Strands agent on AgentCore runs `mlflow.strands.autolog()` with the tracking URI set to the
Databricks workspace, and every agent, model, and tool span lands in a Unity Catalog Delta table.
Tool spans carry the MCP tool name, arguments, result, status, and token usage
([MLflow Strands integration](https://mlflow.org/docs/latest/genai/tracing/integrations/listing/strands/),
[trace agents deployed outside Databricks](https://learn.microsoft.com/en-us/azure/databricks/mlflow3/genai/tracing/prod-tracing-external)).
The AgentCore session id goes on the trace as a tag. The write path records itself through the
procedure. Query history becomes corroborating evidence rather than the primary record, so the
day-one check on whether the functions endpoint leaves query-history rows no longer gates the
design.

**Two checks this adds.** Whether MLflow autolog and the ADOT instrumentation for CloudWatch
coexist in one Runtime container (both are OpenTelemetry; MLflow documents a tracer-provider
setting for merging spans). And the AgentCore session-id format constraints, since the eval's
case-id-plus-run scheme has to fit them.

**Pin MLflow.** The tool-call scorers failed on Strands traces until a format fix landed
([issue 21487](https://github.com/mlflow/mlflow/issues/21487), [PR 21552](https://github.com/mlflow/mlflow/pull/21552)).
Use a release that contains it.

## Gap 3: the eval harness shape

`mlflow.genai.to_predict_fn` supports only Databricks model-serving endpoints and Databricks
Apps, so AgentCore needs a custom `predict_fn`, and MLflow then scores only input and output
([FAQ](https://mlflow.org/docs/latest/genai/eval-monitor/faq/)). The better path: invoke AgentCore
three times per question from the notebook, let the agent's own autologged traces land in the
experiment, search them by the session tag, attach expectations, and evaluate those traces with
`ToolCallCorrectness` and the built-in judges. That scores the deployed agent's full trajectory,
not a proxy. Verify on day two; the custom `predict_fn` is the fallback.

## Verified, no gap

| Item | Finding |
|---|---|
| Service principal to Databricks MCP | OAuth M2M at `https://<workspace>/oidc/v1/token`, client credentials, scoped secrets (`unity-catalog`, `genie`, `sql`) ([OAuth M2M](https://docs.databricks.com/aws/en/dev-tools/auth/oauth-m2m)). Databricks MCP servers accept confidential clients ([connect clients](https://docs.databricks.com/aws/en/agents/mcp-tools/connect-clients)). |
| Strands to Gateway | `MCPClient(url=..., auth={client_id, client_secret})` does client credentials natively; IAM SigV4 inbound via `mcp-proxy-for-aws` needs no Cognito ([MCP transports](https://strandsagents.com/docs/user-guide/sdk/tools/mcp-transports/), [Gateway MCP clients](https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/gateway-using-mcp-clients.html)) |
| Gateway to Databricks | MCP-server targets support OAuth client credentials with a custom provider; a published sample does exactly this with Cognito inbound and OAuth outbound ([sample](https://github.com/awslabs/agentcore-samples/tree/main/06-workshops/03-AgentCore-identity/11-gateway-inbound-outbound-auth)) |
| Genie under a service principal | Allowed with `CAN RUN` on the agent plus `SELECT` on the tables; billed, not free; the MCP endpoint is read-only, passes no history, and may need polling ([Genie API](https://docs.databricks.com/aws/en/genie-agents/conversation-api), [Genie cost](https://docs.databricks.com/aws/en/genie/monitor-cost), [managed MCP](https://learn.microsoft.com/en-us/azure/databricks/generative-ai/mcp/managed-mcp)) |
| USAJOBS key | Request form is live and asks only for contact details and terms acceptance ([request](https://developer.usajobs.gov/apirequest/)); Historic JOA and code lists need no key |

## Day-one verification list

1. Managed MCP Servers preview enabled by a workspace admin.
2. `CALL stage_briefing_item(...)` through the MCP functions server; if not, through the
   Statement Execution API.
3. UC functions as tools run on serverless generic compute, not the SQL warehouse; confirm which
   SKU the MCP functions server bills to.
4. MLflow autolog plus ADOT in one Runtime container; AgentCore session-id constraints.
5. Genie Agent MCP latency under a service principal, since polling lands on p95.
6. Procedures and fine-grained DML grants in the commercial region (IL5 table shows DML
   privileges available; procedures unverified there).

## Not gaps

The golden question list, the ontology object list, and the OMB Table 16.1 crosswalk for DHS are
spec and build work, not research.

## Answered by Ryan (2026-10-30 evening)

- No interview date yet. The hard cutoff is the last commit by Thursday 2026-11-05 at 17:00;
  the recruiter is notified on completion and scheduling follows.
- The USAJOBS Search API key is in hand. It goes in a secret store, never in the repo; the hooks
  and gitleaks CI are the backstop.
