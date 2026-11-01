# Spec 05: the prototype agent and the session traces

**Goal.** A working agent that a human can question this afternoon, built so that every turn
leaves the trace spec 04 requires. One Strands agent on Claude Haiku 5.5 reaches the eight
`semantic` functions and the Genie space over the Databricks MCP endpoints as the read-only
service principal, labels every answer Verified or Exploratory, labels every imputed or synthetic
value, refuses what is out of scope, and ends every answer with a structured block the scorers
grade. A terminal session loop runs the tester's questions; a harness with the spec 04 `invoke`
interface runs the frozen set three times and writes `eval.runs`. After this spec, the first
pass^3 can be measured locally, before anything is deployed.

**Scope, decided 2026-11-01.** Defaults stated rather than asked:

- **Direct MCP, Gateway deferred.** The agent calls the two workspace MCP endpoints directly with
  the service principal's OAuth token. The MCP-path decision's Revisit clause permits this ("fall
  back to direct calls and log it"); the reason is a user session today. AgentCore Gateway and
  Runtime arrive in spec 06 with no change to the agent code. The governance that matters
  survives the fallback: the token carries the `unity-catalog` and `genie` scopes only, so a SQL
  tool is refused at the token, and the principal holds no write grant anywhere
  ([freeform SQL vs governed tools](../../wiki/analyses/freeform-sql-vs-governed-tools.md)).
- **Terminal, not a web page.** The static concept pages stay in the browser for the brief and
  the quarter list. The live assistant runs in a terminal with a large font on the shared
  screen; Ryan types the tester's words verbatim, which is also the log. A web page would cost the
  afternoon and test nothing the eval needs.
- **Structured answer by contract.** Every answer ends with a fenced JSON block holding
  `answer_value` and `cited_tools`. The wrapper parses it, strips it from the displayed text, and
  stores the fields. A missing or malformed block does not fail the turn: the row still writes
  with `answer_value` null and `error = format`, distinct from a tool or model error, so the
  formatting miss rate is its own number as spec 04 requires. No second model call for
  structured output; it would double cost and latency per turn.
- **Model.** `claude-haiku-5-5` through the Strands `AnthropicModel` provider, `max_tokens`
  16000 (thinking tokens count toward the cap, and a truncated answer loses the trailing block),
  no sampling parameters (Haiku 5.5 rejects non-default values), `cache_config` set so the system
  prompt carries a cache point. Thinking is on by default at effort `medium`; the spec does not
  configure it. **No fallback model in the prototype** (Ryan, 2026-11-01). The Model decision's
  OpenAI fallback is deferred to spec 06 or dropped there; today an Anthropic outage is handled
  by the during-session list in step 3. `provider_served` stays on every row and reads
  `anthropic` throughout.
- **Built blind.** The prototype and its prompt are written this afternoon before any question
  exists, which is the uncontaminated order. Spec 04's rule that Ryan's rows precede prompt
  tuning still holds: any prompt change after the rows exist shows as a new `prompt_hash`.
- **Governance, stated plainly.** Read-only rests on grants: the principal holds `USE CATALOG`,
  `USE SCHEMA`, `EXECUTE`, and `SELECT` on `semantic` and nothing else, and its token scope
  excludes the SQL tool. Scope refusal (an individual, another department, budget) rests on a
  prompt rule measured by the refusal line of the eval, not on a grant: Genie can run any
  `SELECT` over the row-level semantic views, which carry OPM pseudo-identifiers and no names.
  Say both halves when asked.
- **Fresh run.** A new `Agent` instance per eval run, nothing shared between runs, a new
  `session_id`. Two-turn rows call `invoke` twice on the same instance and are graded on the
  second answer ([spec 04](04-eval-set.md), step 6).
- **Prompt hash.** SHA-256 over the system prompt file and every skill file, computed at start
  and written on every trace line. The prompt text lives in `challenge/prototype/prompt.md`, not
  in this spec, so the hash means something.

**Out of scope.** AgentCore Gateway, Runtime, Observability, and the AI/BI dashboard (spec 06);
the scheduled Lakeflow job (spec 06); any UI beyond the terminal; writing anything to Databricks
as the agent (it cannot); a ninth function for accessions by month (logged for spec 06 if the
context-supplied class needs it Verified rather than Exploratory). The one infrastructure change
this spec may make is conditional: `CAN USE` on the warehouse for the service principal if step
1 shows Genie needs it, applied through Terraform and logged. Genie usage then bills under the
principal, which the MCP-path decision already accepts.

**Implements.** Agent layer, Model, Agent topology, MCP path (Revisit clause, amended
2026-11-01), Domain model (read-only) in `DECISIONS.md`; the hand-off list in
[spec 04](04-eval-set.md).

**Identities.** The agent is the service principal for every Databricks call. Ryan's user runs
the session loop and the harness, and owns the `eval` tables the harness writes. The Anthropic
key comes from the environment and is never written to a trace.

**Rule.** As spec 01: no workspace URL, user name, warehouse id, space id, or key in a tracked
file or a trace line. Traces under `raw/` are gitignored. The forbidden-terms hook applies.

**Budget.** Haiku 5.5 is $0.10 per million input tokens and $0.50 per million output. A turn
with the system prompt, skills, two tool calls, thinking, and an answer is roughly 8,000 input
and 2,000 output tokens, about $0.002. The session (40 turns) and a full eval pass (about 120
calls) each cost under $0.50 in model tokens; the Sonnet judge on narrative rows adds under
$0.10 per pass. Warehouse time is the larger cost: the 2X-Small warehouse's auto-stop stays at
five minutes as Terraform has it, and a 45-minute session plus an eval pass keeps it warm for two
to three hours. Expect $5 to $8 for the day.

**Files.** Created by this spec: `challenge/prototype/agent.py` (agent construction, MCP
clients, trace writer), `challenge/prototype/prompt.md` and `challenge/prototype/skills/` (the
system prompt and skill files), `challenge/prototype/session.py` (the terminal loop),
`challenge/scripts/eval_harness.py` (the `invoke` interface, stub, writes to `eval.runs`),
`challenge/prototype/requirements.txt`, this spec and `05-results.md`. Changed:
`challenge/example.env` gains `ANTHROPIC_API_KEY`. Reused by copy, not import: the token and
transport code in `challenge/scripts/mcp_smoke.py` (it runs at import and reads the environment
at module level).

## Step 0: the environment

Pin `strands-agents`, `mcp`, `httpx2`, `anthropic`, `pyyaml` at their installed versions in
`requirements.txt`; nothing new is installed. Set `ANTHROPIC_API_KEY` in `challenge/.env`.

## Step 1: the first check this afternoon

Run 2026-11-01 13:10 by a reviewer agent, read-only; all four checks passed and no Terraform
change was needed. Findings in `05-results.md`. The checks as specified:

1. Genie as the service principal. Call the Genie MCP endpoint with the smoke script's token and
   ask one question. If it fails on warehouse permission, add `CAN USE` on the warehouse for the
   principal in `challenge/infra/main.tf` and apply; record it in `05-results.md` and amend the
   Terraform decision.
2. Serialization of `open_postings` (an `ARRAY<STRING>` column) and `plan_variance` (the long
   `generation_rule` string) over MCP. Call both once and keep the raw tool result text in the
   results file, with the space id redacted if the Genie tool's name or output carries it.
3. The Genie tool's real name over MCP. If it embeds the space id, the trace writer's
   normalization (step 2) is what keeps it out of every tracked file.

## Step 2: the agent

`challenge/prototype/agent.py` exposes one function, `build_agent(session_id) -> Agent`, and one
wrapper, `run_turn(agent, text, q_id=None, context=None) -> dict`, plus the trace writer.

**Transport and tools.** Two `MCPClient` instances whose factories build the transport exactly
as `mcp_smoke.py` does: `streamable_http_client(url, http_client=httpx2.AsyncClient(headers=
{"Authorization": "Bearer <token>"}, timeout=60))`, minting the token inside the factory with
the client-credentials call and scope `unity-catalog genie`, so every new client gets a fresh
token. The docs' `streamablehttp_client(headers=...)` form is for mcp 1; this environment runs
mcp 2 and the smoke script is the known-good construction (Strands 1.63 also accepts
`MCPClient(url=..., headers=...)`; either is fine, the sixty-second timeout is not optional
because Genie exceeds the five-second default). Client one points at the schema-level functions
URL (`/api/2.0/mcp/functions/workforce/semantic`, confirmed in spec 03 results to list all eight
tools). Client two points at the Genie URL (`/api/2.0/mcp/genie/<space id>`). The two clients
are passed directly into `Agent(tools=[functions_client, genie_client])` as tool providers, so
their lifetime follows the agent and no `with` block closes them when `build_agent` returns.
Client-credentials tokens live one hour (`expires_in: 3600`, step 1), so the session agent is
built at the tester's first question, not at setup, and `/new` is the recovery for a 401.

**Genie as one local tool.** The Genie endpoint exposes two MCP tools whose names embed the space
id: a query tool that returns `EXECUTING_QUERY` with a conversation id and message id after about
fifteen seconds, and a poll tool that returns `COMPLETED` with the generated SQL, a statement id,
and rows about thirty seconds after submission (step 1). Rather than let the model drive the
poll loop (two or three model calls and the space id in every tool result), the Genie client is
not handed to the model directly. A local Strands tool `one_off_query(question)` calls the query
tool through the Genie `MCPClient`, polls until `COMPLETED` or 120 seconds, and returns a compact
result: `sql`, `statement_id`, `columns`, `rows` (cast from Genie's all-string cells to numbers
where the column is numeric), `truncated`, and `row_count`, with the space id removed from any
text. The model sees one tool named `one_off_query`; the trace records it as `genie` with
`genie_sql` and `genie_statement_id` filled from the result. When Genie returns a breakdown
without a total for a "how many" question (step 1: 49 state rows, no sum), the agent sums the
rows and says so, under rule 9.

**Model.** `AnthropicModel(client_args={"api_key": ...}, model_id="claude-haiku-5-5",
max_tokens=16000, cache_config=...)`. No router and no fallback. A connection, 5xx, or
overloaded error surfaces from the turn as `error = model` on the trace line; the Anthropic
SDK's own retries (two by default) are the only automatic recovery, and the session list in step 3
is the manual one.

**Callbacks and output.** `Agent(..., callback_handler=None)`. The default handler streams every
token and prints `Tool #1: workforce__semantic__headcount` on the shared screen before the
wrapper can strip anything, which breaks rule 1 in front of the tester. The session loop prints
after the turn, with a "working..." line while a tool runs. The Strands console span exporter is
set up with `setup_console_exporter(out=<spans file>)` so spans go to the file, not stdout.

**System prompt and skills.** `prompt.md` carries the rules; `skills/` carries the briefing
format, the component and series code lists with their plain names, and the label vocabulary.
Skill files are concatenated into the system prompt in sorted filename order; the Strands
`AgentSkills` mechanism is not used, since it adds a tool call per turn. The rules, which the
spec 04 scorers map to one for one:

1. Speak in human-capital vocabulary on screen: staffing plan, variance, separations,
   mission-critical occupations. Never name Databricks, Genie, Unity Catalog, or a function name
   in the prose; call the functions "the review's standard calculations" and Genie "a one-off
   query."
2. Open every answer with its label line: `Verified` when every number came from the function
   tools, `Exploratory` when any number came from the Genie tool, `Not available` for a refusal
   or a data limit, `Question` for a clarifying reply. Show the generated query verbatim for
   Exploratory answers; the query text is the one place a schema name may appear on screen.
3. Say "estimated" or "imputed" whenever a tool result carried `headcount_location_imputed`
   greater than zero, or a Genie row carried `location_imputed` or `pay_imputed` true. No other
   function output carries an imputation column (`rows_imputed` on `imputation_quality` is a
   masking-test count, not rows the answer rests on). Say "synthetic," "generated," or "demo
   plan" whenever the staffing plan is cited (`is_synthetic` on `plan_variance`).
4. Refuse an individual, another department, budget and appropriations, and why someone left,
   and name the nearest in-scope alternative.
5. When the data cannot answer an in-scope question (no start snapshot for the month, no plan
   before FY2026 Q1), say which limit applies and offer the nearest answerable variant.
6. When intent is ambiguous, ask one clarifying question that names the readings, and call no
   tool first.
7. When the user supplies a fact the data lacks, recompute under it, state it as the user's
   assumption with the arithmetic shown, and never present it as a discovered fact.
8. End every answer with a fenced block tagged `json` holding exactly `{"answer_value": <number
   | [{"key":..,"value":..}] | null>, "cited_tools": [<tool names or "genie">]}`. The wrapper
   accepts the last fenced block whether or not the tag is present, so a dropped tag is not a
   `format` error; only a missing block or unparseable JSON is.
9. Never invent a number; every number in the prose comes from a tool result in this turn or is
   arithmetic shown step by step from such numbers.
10. Call at most one tool per question unless the question names two cells to compare;
    `imputation_quality` may accompany `headcount` on a location answer, as its comment asks.
    `one_off_query` counts as one call; the polling happens inside it.

The agent's system prompt is passed as the Anthropic provider's system content; whether a cache
point on it is honored by this provider is checked in acceptance by reading
`cacheReadInputTokens` on the second turn.

**Trace writer.** After each turn, one JSON line to `raw/<date>-<session>-trace.jsonl` built from
`agent.messages` (the tool-use and tool-result blocks since the previous turn) and the usage of
the latest invocation (`metrics.agent_invocations[-1].usage`, or the difference of
`accumulated_usage` against the previous turn; the accumulated counter is cumulative across the
session and must not be written per turn as is). Fields, every one in spec 04's hand-off plus
the additions named: `ts` (ISO 8601, UTC), `session_id`, `run_index`, `set_version` (the
questions file header, `eval-v1`, even while unfrozen), `q_id` (auto-incremented `A01, A02...`
per turn, `/q` overrides), `agent_git_sha` plus `git_dirty`, `prompt_hash`, `model_id`,
`provider_served`, `stop_reason`, `question_text`, `supplied_context`, `turn_1_answer_text`,
`tool_calls` (each with `name`, `params`, `result_rows`, `imputed_rows`, `synthetic_rows`,
`duration_ms`; the two counts are the sum of `headcount_location_imputed` and the count of
`is_synthetic = true` rows when those columns are present and zero otherwise; `duration_ms` from
wall clock around the tool-result delta), `genie_sql` and `genie_statement_id` (read from the
Genie tool result when present; else the message id, as spec 04's fallback allows),
`answer_text` with the JSON block stripped, `answer_value`, `cited_tools`, `latency_ms`,
`input_tokens`, `output_tokens`, `cache_read_tokens`, `cost_usd` (at the serving provider's
prices, with cache reads at the cache price), `error` (`null`, `format`, `tool`, `model`,
`max_tokens`, `refusal`; `tool` is set only when the turn ended on a tool error, not when the
model recovered from one).

**Tool-name normalization.** MCP names the functions `workforce__semantic__<fn>`; spec 04's
`expected_tools` uses bare function names and the word `genie`. The trace writer strips the
prefix and records `one_off_query` as `genie`, in both `tool_calls` and `cited_tools`. Without
this the `tool_use` and `provenance` scorers fail by construction. The space id appears in Genie
tool names and in Genie result text (a prose line that names the poll tool), so the
`one_off_query` wrapper redacts it from every string before anything reaches the model or the
trace. Function results carry a top-level `is_truncated` flag; the trace records it per call.

The Strands console exporter writes spans to `raw/<date>-<session>-spans.log` for the
span-level record; it is not parsed.

## Step 3: the session loop

`challenge/prototype/session.py`: a terminal loop over one agent instance for the whole tester
conversation (one `session_id`), built at the first question. Commands: `/q A07` tags the next
turn with a log id; `/context <text>` sends the next turn as supplied context (rule 7), delivered
as a user message that opens "The analyst supplies this fact, which the data does not contain:";
`/new` starts a fresh agent instance, token, and session id. Plain text is sent verbatim. The
answer prints with the label line first, then the prose, then one dim line with the tool names
and latency for Ryan's eyes. Every turn writes a trace line; nothing else is logged. Font and
window are set before the tester arrives.

**Two-turn plumbing.** A `/context` turn writes its own trace line whose `turn_1_answer_text` is
the previous turn's answer and whose `supplied_context` is the fact. The harness, for a
context-supplied row, calls `invoke` twice on one agent and writes one `eval.runs` row from the
second line, summing `latency_ms`, tokens, and `cost_usd` over both.

**During the session.** Never debug on the shared screen. On any exception: say "one moment,"
type `/new`, re-ask. On a Genie failure or timeout: the agent answers from a function if one
fits, otherwise says the one-off query is not available in this demo; the line carries `error =
tool`. On a 401: `/new`. On a model error that the SDK's retries do not clear: the question goes
in the log with `answered_by = none` and the session continues on the static pages. If the model
skips the label line or the block, the answer still prints; the trace records the miss.

## Step 4: the harness

`challenge/scripts/eval_harness.py`:

- `invoke(question, session_id, context=None)` returns the spec 04 dict, built from `run_turn`.
  A `--stub` flag returns "no answer" with null fields for the dry run.
- `run(set_version, runs=3)` loads `challenge/eval/questions.yaml`, and for each question and
  each run index builds a fresh agent, calls `invoke` (twice for two-turn rows, with the
  supplied context on the second call), applies the spec 04 scorers against the truth columns,
  and writes one `eval.runs` row through the Statement Execution API with the configured
  warehouse, using `httpx` (already installed) and a token from `databricks auth token -p
  workforce` run as a subprocess, so the write happens as Ryan's user, which owns `eval`; the
  service principal has no grant there. Narrative rows also write an `eval.judge` row from a
  `claude-sonnet-5-5` call with the versioned prompt in `challenge/eval/judge-prompt.md`.
- `load-session <trace.jsonl>` writes the tester session as `run_index = 0` rows, joining each
  line's `q_id` to the questions file, so the spec 04 calibration view has data, and uploads the
  trace file under `eval/` in the `bronze.landing` volume as spec 04 step 1 requires.
- Scorers are plain functions in the same file, one per spec 04 scorer, each returning pass or
  fail and nothing else.

## Step 5: acceptance

1. The service principal's token lists eight tools on the functions endpoint and the Genie tools
   on the Genie endpoint; the step 1 checks are recorded.
2. One Verified turn (a question the eight families cover) returns a `Verified` label, a parsed
   `answer_value`, and `cited_tools` naming the function that ran.
3. One Exploratory turn returns an `Exploratory` label, the generated SQL in the prose, and
   `genie_sql` on the trace line.
4. A refusal probe, a data-limit probe, and an ambiguous probe each produce the expected behavior
   with `answer_value` null and no tool rows returned.
5. A `/context` turn supplying the lapse dates produces an answer that states the assumption and
   shows the arithmetic.
6. A turn with the Anthropic `base_url` pointed at a dead local port writes a trace line with
   `error = model`, the session loop prints its "one moment" line instead of a traceback, and
   `/new` recovers.
7. The second turn of a session shows `cache_read_tokens` greater than zero, or the results file
   records that the provider did not cache and the budget line is restated.
8. `eval_harness.py --stub` writes one synthetic row to `eval.runs` (the questions file is empty
   until the session) and `load-session` on this afternoon's trace writes `run_index = 0` rows
   and uploads the trace to the volume. The tables come from spec 04's `04_eval.sql`, which is
   run first and is a dependency of this check, not a product of this spec. The stub run never
   calls the judge; the three views are checked in spec 06 once real rows exist.
10. The tool-name normalization holds: no `workforce__semantic__` prefix and no space id appears
    in any trace field or in `05-results.md`.
9. `git grep -iFf .forbidden-terms --untracked` prints nothing; no trace file is tracked.

## Results file

`challenge/specs/05-results.md`: the step 1 findings and raw tool results; the session's turn
count, formatting miss rate, mean latency, tokens, and cost; the dead-port error test; the cache check;
the dry run output; the first local pass^3 once the set is frozen, labeled as a direct-MCP local
run; anything that differed from this spec.

## Teardown

Nothing beyond spec 01. Trace files stay under `raw/`.

## Settled before writing (2026-11-01)

- The schema-level functions MCP URL lists all eight tools, prefixed `workforce__semantic__`,
  and `separation_rate` was called over it as the service principal (spec 03 results).
- The token call is `POST /oidc/v1/token` with client-secret basic auth and scope `unity-catalog
  genie`; `all-apis` is refused (`mcp_smoke.py`).
- Strands 1.63.0, mcp 2.3.0, httpx2, anthropic 0.125.0, and pyyaml are installed in
  `challenge/.venv`; `openai` and `databricks-sdk` are not, and neither is needed.
  `AnthropicModel` takes `client_args`, `model_id`, `max_tokens`, `params`, `cache_config`;
  `MCPClient` is a tool provider that can be passed to `Agent(tools=...)`; usage per invocation
  is on `metrics.agent_invocations`; `agent.messages` holds the tool-use and tool-result blocks.
- Flag columns on function outputs: `headcount_location_imputed` on `headcount` only;
  `is_synthetic` on `plan_variance` only; no imputation column on the other six.
- The warehouse auto-stop is five minutes in Terraform.
- Step 1 (2026-11-01): the token lives 3600 seconds; the functions endpoint lists all eight
  tools; `open_postings` serializes `states` as a nested JSON array (six of eleven CBP Officer
  postings open on 2026-08-01 carry `[null]`, a data fact, not a transport fault); `plan_variance`
  returns the 248-character `generation_rule` intact; function results carry `is_truncated`;
  Genie runs as the service principal with no extra grant, through a two-step query-then-poll
  flow whose results carry the generated SQL, a statement id, conversation and message ids, and
  rows with every cell typed as a string. Cold warehouse first call 25 seconds, warm 1.5.
- Spec 04's hand-off list and `invoke` interface are the contract this spec implements.
- Haiku 5.5 prices: $0.10 and $0.50 per million tokens for prompts under 100K tokens.

## Not verified before writing

- Whether Genie ran as the service principal on its own grant or with the space owner's rights;
  it worked, and the distinction matters only for the deep dive.
- How long an immediate poll loop takes against the thirty-second figure measured with a gap.
- Which span attributes the Strands console exporter populates for the Anthropic provider.
- Whether `cache_config` on `AnthropicModel` produces cache reads on the second turn
  (acceptance 7).
- The client-credentials token lifetime; `/new` is the stated recovery either way.
- Whether one Statement Execution call accepts the array-of-struct `tool_calls` column, or the
  harness must stage it as a JSON string and cast in SQL.
- How often Haiku 5.5 omits or malforms the trailing JSON block (the formatting miss rate).
