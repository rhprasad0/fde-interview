# Spec 05 results

## Step 1: pre-build checks (2026-11-01, 13:10, read-only, run by a reviewer agent)

All four passed. No Terraform change. Host, client id, secret, token, and space id were never
printed; the raw outputs are in the session scratchpad, not the repo.

| Check | Result |
|---|---|
| Token | `POST /oidc/v1/token`, client-secret basic auth, scope `unity-catalog genie`; response scope `genie unity-catalog`, `expires_in` 3600 |
| Functions endpoint | Lists eight tools prefixed `workforce__semantic__`. `open_postings('2026-08-01','HSBD','1895')`: 11 rows, `is_truncated` false, `states` is a nested JSON array (`["Vermont"]`); six rows carry `[null]` because those postings have no state in their location data. Cold call 25.3 s, warm 1.5 s. `plan_variance('FY2026Q1','HSBD','1895')`: one row `[594, 475, -119, -0.2003, true, <rule>, 1, 7]`; the 248-character `generation_rule` arrived intact. 2.5 s |
| Genie endpoint | Two tools, names embed the space id: a query tool (`query: string`, optional `conversation_id`) and a poll tool (`conversation_id`, `message_id`). Asked "How many CBP Officers (series 1895) were employed in August 2026?": the query tool blocked about 15 s and returned `EXECUTING_QUERY` with conversation and message ids, empty query attachments, and a prose line naming the poll tool (space id inside). One poll about 30 s after submission returned `COMPLETED` with `queryAttachments[0].query` (a trusted-function call: `headcount` for 2026-08-01, HSBD, 1895), `queryAttachments[0].statement_response.statement_id` (a UUID, `SUCCEEDED`), and 49 rows by state in `result.data_array` with every cell as `string_value`, including the integers. No prose, no total, three suggested questions. About 30 KB |
| Permission | Not triggered: Genie ran as the service principal without a `CAN USE` grant |

Consequences carried into the spec:

- Genie is wrapped in one local tool, `one_off_query`, that runs the query-then-poll flow,
  casts string cells to numbers, and redacts the space id from tool names and result text.
- The agent sums Genie breakdowns when a "how many" question comes back without a total.
- Function results' `is_truncated` flag is recorded per tool call.
- The harness must compare Genie numbers after casting; Genie's state names are upper case
  (`TEXAS`) while `open_postings.states` is title case (`Vermont`).

Surprises: the space id appears in Genie result text, not only in tool names. mcp 2.3 names the
result fields `is_error`, `structured_content`, and `input_schema` (snake case); the smoke script
does not touch them and still works.

Not measured: an immediate poll loop; the thirty seconds includes a gap between processes.

## Build and acceptance (2026-11-01, 13:30 to 14:00, built by an Opus reviewer agent, spot-checked by the lead)

Files: `challenge/prototype/agent.py` (302 lines), `session.py` (54), `prompt.md` (52),
`skills/01-briefing-format.md`, `skills/02-codes.md`, `skills/03-labels-and-limits.md`,
`requirements.txt`; `challenge/scripts/eval_harness.py` (311); `example.env` gains
`ANTHROPIC_API_KEY`. Run the session with `challenge/.venv/bin/python -B
challenge/prototype/session.py`. Traces land in `raw/2026-11-01-<session>-trace.jsonl`.

| Check | Result |
|---|---|
| 1 Tool listing | Pass. Eight function tools; two Genie tools |
| 2 Verified | Pass. TSA screener separation rate: label `Verified`, `answer_value` 0.1202, `cited_tools` `["separation_rate"]`. Lead's own run: CBP Officer rate 0.0351 in 4.3 s, HR vocabulary, no tool names on screen |
| 3 Exploratory | Pass. CBP Officer accessions by month through `one_off_query`: label `Exploratory`, SQL shown, `genie_sql` and `genie_statement_id` on the trace, `answer_value` a six-pair list. A pay question said "imputed" |
| 4 Refusal, data limit, ambiguous | Pass. Three refusals (`Not available`, no tool, alternative offered), two data limits (March 2026 rate; FY2025 Q4 plan), three clarifying `Question` replies; all `answer_value` null |
| 5 Context turn | Pass. After the CBP Officer FY2026 Q1 variance, the lapse dates produced "Assuming, as you state..." with the arithmetic shown (594 x 49/92 = 316.4; 475 against it is +158.6); `supplied_context` and `turn_1_answer_text` filled |
| 6 Dead port | Pass. `error = model`, "one moment" printed, no traceback, `/new` recovered |
| 7 Cache | Pass. Second turn read 14,051 cached tokens; counts are per turn |
| 8 Harness | Dry run only. `--stub --dry-run` builds the one-row insert; `load-session --dry-run` writes zero rows (empty questions file) and prints the upload path. No live write; `04_eval.sql` does not exist yet |
| 9 Forbidden terms | Pass; no trace file tracked |
| 10 Normalization | Pass on every trace field, spans file, and stdout after one fix: the Genie client's span names leaked the space id into a spans log before the exporter was wrapped in the redactor; the file was scrubbed and the cause fixed |

Measured over 20 turns in 5 sessions: format miss rate 1 of 8 on the first prompt (a clarifying
reply dropped the block), 0 of 11 after tightening rules 6 and 8; label line present on all 19
answered turns; latency mean 8.3 s, median 4.2 s (no-tool 2.3 s, functions 5 to 10 s warm and
29 s cold, Genie 27 to 36 s); $0.0094 in model tokens for all 20 turns. Prompt hash in force
`22b1d089...`.

Differences from the spec, kept:

- Two-turn rows merge both turns' tool calls into the row's `tool_calls`; the context answer
  cites `plan_variance` from turn 1, so second-turn-only would fail `provenance` by construction.
- `/context` sends immediately as its own turn; `question_text` carries the prefixed message.
- `one_off_query` opens a fresh Genie MCP session and token per call rather than holding one open.
- Extra trace fields: `cache_write_tokens`, `error_detail`, per-call `is_truncated` and `status`;
  the harness writes only spec 04's six `tool_calls` fields.
- `error = tool` is set when the last tool call of the turn failed; on a forced Genie failure the
  model retried once (two Genie calls) before answering "not available," which bends rule 10.
- One spans file per process; `/new` does not start a new one. Ctrl-C mid-turn prints "one moment."
- `imputed_rows` on `headcount` is the sum of `headcount_location_imputed`, people not rows, as
  the spec words it (27,650 on a CBP question).

Decided by the lead after the build:

- `eval.runs` layout follows the harness: `answer_value` as JSON text, `tool_calls` as an array
  of six-field structs with `params` as JSON text, `cited_tools` as an array of strings, scorer
  columns boolean. Spec 04's `04_eval.sql` is written to match.
- `genie_sql_stored` is scored lazily. `system.query.history` lagged about two hours at build
  time, so the harness records the statement id at run time and the history check runs in a
  later pass; statement `01f1d624...` is the probe for whether this is lag or a visibility gap.
- Cache prices in `cost_usd`: reads at 0.1x and writes at 1.25x the input price (an assumption
  from the API reference; confirm against the bill).
- Judge: until `judge-prompt.md` exists, narrative rows score `fail` with a rationale saying why;
  they never pass silently.

Not verified: any live write to `eval`; the judge call; recovery after the one-hour token expiry;
whether Ryan's user can see the service principal's statements in query history.

## Dry run and round three (2026-11-01, 16:00 to 17:30)

Ryan's own dry run (session `s-090ef514`, 8 turns, 3 decision clicks): every trace field present,
task stamps on every line, no leaks. Four of eight turns were clarifying questions, including
both supplied-context turns (the first had no variance figure in the conversation and asked
instead of fetching one). Changes made in response, all verified with scripted clicks in headless
Chrome against the workspace:

- Context turns carry the open cell and the agent fetches the figures first; two fresh
  sessions gave the same prorated-plan recompute (594 x 49/92 = 316.4; 475 against it is +158.6,
  +50.1%), with the actuals unchanged and no claim that the assumption "explains" anything.
- Clarifying questions retired; the `Question` label is gone. Ten varied turns produced only
  Verified or Not available, each ending with the reading taken and the alternative.
- Effort `high` passed as `params={"output_config": {"effort": "high"}}` and confirmed on the
  outgoing request body.
- The assistant page has a header band; the brief's ask box is prominent.
- "Draft the OPM paragraph" chip, the four-sentence paragraph skill, and a "Final paragraph" box
  saving to `raw/<date>-<session>-paragraph.jsonl` with the task stamp.
- A sixth page, `/feedback`, task 6, saving five answers to `raw/<date>-<session>-feedback.jsonl`.
- A bug found on the way: the function tools' schema types every argument as a required string,
  so the model sent `"null"` for an optional argument and FEMA came back empty. A before-tool
  hook now turns `"null"`, `"none"`, and `""` into real nulls; the trace records the argument
  actually sent.

Known: two sessions building agents at the same instant print one stray tracer-provider line and
the second session's spans file stays empty; trace lines are unaffected. The FEMA prose total
once differed from the row sum (20,159 against 20,208), a model arithmetic slip rule 9 does not
fully prevent.
