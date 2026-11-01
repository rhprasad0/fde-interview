# Spec 04: the eval set, built from human traces

**Goal.** A versioned set of golden questions written only by humans, each with truth computed by
SQL that never touches the agent's own functions, a deterministic scorer set, a pass rule, and the
tables and views the harness writes to. The questions do not exist until the prototype session on
2026-11-01, so this is a process spec: it defines how the session is captured, how questions are
classified, how truth is authored, how the set is frozen, and what the prototype (spec 05) must
emit so every row can be scored. Its own acceptance is structural. The agent's pass^3 is measured
in specs 05 and 06, not here.

**Scope, decided 2026-11-01.** Ryan's answers to the four questions that shaped this spec, plus
the defaults stated rather than asked:

- **Human sources only.** Every question is written by a person: Tester A's verbatim questions
  from the 2026-11-01 session, and Ryan's own questions written afterward as a domain-literate
  analyst. No question is generated, paraphrased, or expanded by a model. Reason: the set measures
  the real question distribution of a Human Capital professional; a simulated user measures the
  simulator. A tester paraphrase of an earlier question is kept as its own row with
  `paraphrase_of` set, because robustness to rewording is a property worth grading.
- **Ryan's rows fill, they do not dominate.** Ryan writes his rows after the tester rows are
  classified and before any eval run, to reach a floor of 20 graded questions and to give every
  one of the eight function families at least one question. Each row carries `author`, so the
  panel sees the uncontaminated sample and the coverage fill as separate lines.
- **Numbering.** 04 eval set (this), 05 prototype agent and session traces, 06 AgentCore
  deployment and the AI/BI dashboard. The 2026-10-30 Evaluation decision is amended.
- **Truth grades; the tester's label sits beside it.** Pass or fail comes from SQL truth. The
  tester's judgment of an answer (right, wrong, unsure, would not quote) is a second column, used
  to calibrate the LLM judge and to flag questions whose specification was wrong.
- **Verbatim in the repo, tester anonymized.** Questions and labels are committed as the eval
  source file, attributed to `tester_a` with role only (former federal HR professional, current
  contractor in an unrelated field, not a Palantir user). No name, employer, or recording in the repo. Ryan confirms
  consent before the session. Any name or employer the tester speaks is stripped from the verbatim
  text and noted as `[redacted]`.
- **Truth is independent of the agent.** Truth SQL runs against `synthetic.*` and `silver.*` base
  tables and never calls a `semantic` function or view. A bug in `plan_variance` must fail the
  eval, not pass it.
- **The data state is pinned.** Files through August 2026, loaded 2026-10-31, recorded in the
  questions file header as `data_as_of`. Truth values are stored with the set; a re-run of truth
  SQL must reproduce them before any eval run. A new OPM file changes truth, so it bumps the set
  version. Nothing in this spec waits for the September file.
- **Freeze.** A set version is a git tag (`eval-v1`, `eval-v2`). After the tag, rows never change;
  corrections create the next version. Every results row carries `set_version`. This answers "did
  you tune the questions after seeing failures."
- **Headline scope.** pass^3 at 80% over Verified-tier graded rows (number, list, narrative,
  context-supplied). Narrative rows are the only model-judged rows inside that headline, and the
  summary says so. Genie-tier rows are reported on their own line against the 70% bar already
  decided, with a floor of ten rows so the line is a measurement. Refusal and data-limit rows
  are reported on their own lines and never folded into the headline, so perfect refusals
  cannot hide wrong answers. Reading-stated rows are Verified-tier and count in the headline.
- **Two-turn cases are allowed, few, and scored on the final turn.** The context-supplied class
  (the analyst adds a fact the data lacks, such as the 2025-10-01 to 2025-11-12 lapse in
  appropriations, and the agent recomputes) is graded on the second answer, with the supplied
  context stored on the row.
- **Judge.** One LLM judge for narrative faithfulness only, a different model from the agent
  (`claude-sonnet-5-5` when the agent runs Haiku; confirm the API id on day one, as the Model
  decision does for the fallback), with its prompt versioned in the repo and its rationale stored
  on every row.

**Out of scope.** The agent, its prompt, and its tools (spec 05); AgentCore, the dashboard, and
the scheduled job (spec 06); MLflow (day-five stretch, unchanged); any question written by a
model; any question about an agency other than DHS.

**Implements.** Evaluation (2026-10-30, amended 2026-11-01), Agent topology (2026-10-30), Genie
measured (2026-10-31) in `DECISIONS.md`; the trace requirements in
[what traces the evals need](../../wiki/analyses/executive-agent-demo-wow.md) are restated in the
hand-off section below.

**Identities.** Ryan's user owns the `eval` schema objects and runs the loader and the harness.
The agent's service principal has no grant on `eval`; the harness sends it each question as a
user would, and it never sees the truth, the tester labels, or the scorer results.

**Rule.** As spec 01: no workspace URL, user name, warehouse id, or space id in a tracked file.
No tester name or employer anywhere. The forbidden-terms hook applies to every file here.

**Budget.** Under $1 for this spec. Truth SQL runs once per set version on the 2X-Small
warehouse. The harness runs (three calls per row plus one more per two-turn row, about 100 to
120 calls per pass with 20 Verified and 10 Genie rows) are costed in specs 05 and 06.

**Files.** Exist now: `challenge/eval/questions.yaml` (the set, header only until the session),
`challenge/eval/sessions/2026-11-01-tester-a-log.csv` (the log template), this spec. Created by
the steps below: `challenge/scripts/validate_questions.py` (step 4),
`challenge/notebooks/04_eval.sql` (step 5), `challenge/eval/judge-prompt.md` (step 6),
`04-results.md`.

## Step 1: capture the session (2026-11-01, before anything else)

The tester and the facilitator both watch the three-minute briefing video before the session
(<https://youtu.be/5UgPAHnXmUE>, made from `challenge/eval/sessions/2026-11-01-tester-briefing.md`
and the four screenshots beside it). Ryan chose to show the screens in advance so the tester is
not blindsided; the test measures how they use the screens, not whether they can find them.

The session log is the raw material. The template exists before the tester arrives:
`challenge/eval/sessions/2026-11-01-tester-a-log.csv`, one row per question the tester asks or
would ask, with these columns:

| Column | Meaning |
|---|---|
| `q_id` | `A01`, `A02`, ... in the order asked |
| `asked_at` | wall-clock time, minute resolution |
| `task` | 1 to 5 from the session plan (read the brief, triage, explain, decide, break it) |
| `screen` | `brief`, `quarter`, `ask`: the three screens of the concept prototype shown in the session (the draft explanation for one cell, the ranked cell list for the quarter, the follow-up assistant) |
| `verbatim` | the question as spoken or typed, names and employers replaced by `[redacted]` |
| `answered_by` | `static_page`, `live_agent`, `none` (what the tester saw in response) |
| `tester_judgment` | `right`, `wrong`, `unsure`, `would_not_quote`, or blank when nothing answered |
| `wanted_next` | what they said they would ask or look for next, verbatim |
| `clicked` | any accept, reject, or flag the tester chose, and on which recommendation |
| `facilitator_note` | hesitation, vocabulary mismatch, caveat read or skipped, intervention |

Rules during the session: record it (with consent) and fill `verbatim` from the recording the
same evening, never from memory; during the session note only `q_id`, `asked_at`, `task`,
`clicked`, and the judgment, so the think-aloud is not interrupted. Never rephrase a question; if
the tester asks the same thing twice in different words, both are rows. The recording stays out
of the repo. The tester's judgment
is of whatever they were shown. Where a live agent answered, the judgment calibrates the judge;
where a static page answered, it tells you whether the brief's content is right, and the row
still becomes a question.

Redaction applies to every free-text column (`verbatim`, `wanted_next`, `facilitator_note`), not
only the question. Before the log is committed, the tester's name and employer go into the local
`.forbidden-terms` file, so the pre-commit hook enforces the anonymity rule rather than trusting
a read-through.

If a live agent runs during the session, its trace (spec 05 format) is saved to
`raw/2026-11-01-tester-a-trace.jsonl` (gitignored) and uploaded under `eval/` in the existing
`bronze.landing` volume; no new volume is created. The log CSV is committed; the trace is not.
The session trace is later loaded into `eval.runs` as `run_index = 0`, so the tester's judgment
and the scorers can be compared on the same answer.

## Step 2: classify every row

After the session, each log row becomes a candidate question with a `class` and an
`expected_behavior`:

| `class` | What it means | `expected_behavior` | Tier |
|---|---|---|---|
| `family_1` to `family_8` | Answerable by one of the eight functions: headcount and location; separation rate; attrition ranking; length of service; open postings; posting coverage; plan variance; imputation quality | `number` or `list` | Verified |
| `exploratory` | Answerable from the semantic views but outside the eight families | `number`, `list`, or `narrative` | Genie |
| `narrative` | Asks for an explanation or a draft (the variance paragraph) that rests on Verified numbers | `narrative` | Verified |
| `context_supplied` | Two turns: the analyst adds a fact, the agent recomputes with a labeled assumption | `number` on the second turn | Verified |
| `refusal` | Out of scope: an individual, another department, budget, why someone left | `refusal` | Refusal |
| `data_limit` | In scope, but this data cannot answer it (a twelve-month rate for a month with no start snapshot; a plan quarter before FY2026) | `data_limit` | Refusal |
| `reading_stated` (was `clarify`; changed 2026-11-01 after the dry run) | Intent is ambiguous; a correct agent answers the most plausible reading for the open cell and ends by stating the reading it took and the nearest alternative, so the analyst can correct it. Clarifying questions are retired: four of eight turns in Ryan's dry run were questions, two of them on supplied context | `number` or `list`, plus the stated reading | Verified |

Rows that are not questions (a comment, a reaction) stay in the log and do not become rows in the
set. Rows with identical `verbatim` text are merged into the earliest row; its judgment survives
and the later judgments go in `notes`. Near-duplicates are kept with `paraphrase_of`.

Then Ryan writes his rows, all before any eval run. The spec 05 prototype and its prompt are
built blind before the session, so the questions never shape the first prompt; any prompt change
after the rows exist shows as a new `prompt_hash`.

- enough to reach 20 graded Verified-tier questions, `reason: floor`;
- at least one per family the tester did not touch, `reason: coverage`;
- ten Genie-tier questions outside the eight families, `reason: genie`, each aimed at one of the
  five likely Genie errors named in the Genie decision (wrong month column; `pay_redacted IS NULL`
  read as redacted; imputed location stated as fact; synthetic plan unlabeled; series matched on
  the first listed code), so the Genie line is a measurement and not two rows.

The coverage report counts paraphrases separately from distinct truths, so a paraphrase cannot
lift the floor.

## Step 3: author truth, independent of the agent

For every `number` and `list` row, Ryan writes `truth_sql` against `synthetic.employment`,
`synthetic.separations`, `synthetic.accessions`, `synthetic.staffing_plan`, `silver.job_postings`,
`silver.places`, and `silver.state_centroids` as needed. Never `semantic.*`, in any spelling. A
`number` truth returns exactly one row with one value. A `list` truth returns key and value
columns, plus a rank when the question asks for a ranking; the value is graded under the row's
`tolerance`, so a by-state question cannot pass on the set of 51 states alone. Truth runs once on
the pinned data; the result is stored on the row as `truth_value` with `truth_computed_at`.

Truth is written with the spec 03 results in view, so disagreement is possible. When a truth value
disagrees with what the corresponding function returns, the disagreement is logged in
`04-results.md` and the fix goes to `03_semantic.sql`, never to `truth_sql`. The functions are
the thing under test.

Two more truth columns are computed by SQL, not by hand, so the caveat scorer is deterministic.
They are computed for every graded row, including narrative, exploratory, and context-supplied
rows, from every truth SQL the row carries:

- `requires_imputed_label`: true when a truth SQL reads a location or pay column (duty station,
  state, point, or pay) and any row it touched has `location_imputed = true` or `pay_imputed =
  true`. A count, rate, tenure, or posting question that reads no such column does not require
  the label even when its rows are imputed elsewhere; the agent sees no imputation flag in those
  function outputs and must not be failed for a label it had no basis to add. For a location or
  pay question about TSA or CBP this is always true.
- `requires_synthetic_label`: true when any truth SQL touches `synthetic.staffing_plan`.

`narrative` rows carry `truth_facts`: a list of `{name, truth_sql, truth_value, tolerance}`, the
numbers the narrative must state correctly, and `must_not_claim`: statements the data cannot
support (retirement eligibility, why people left, an individual).

`data_limit` rows carry `limit_text`: the fact that makes the question unanswerable on this data
(for example, only `2026-08-01` has a start snapshot for a twelve-month rate), and `nearest`: the
answerable variant a good answer offers.

`refusal` rows carry `must_refuse: true` and `must_offer`: the in-scope alternative a good answer
names. `clarify` rows carry `acceptable_readings`: the two or more interpretations a clarifying
question should distinguish.

`context_supplied` rows carry `turn_1`, `supplied_context`, `turn_2`, and truth for turn 2 under
the stated assumption, with `assumption_text` that the answer must label. The recompute
convention, pinned 2026-11-01: a supplied period in which hiring could not happen scales the
planned hires to the days hiring was possible (plan x open days / days in the quarter); the
actuals are never adjusted, since they already reflect what happened. Truth for turn 2 is
computed under that convention. For the FY2026 Q1 lapse (2025-10-01 to 2025-11-12, 43 of 92
days), the CBP Officer plan of 594 scales to about 316 and the 475 actuals land about +50% over it.

## Step 4: the questions file

`challenge/eval/questions.yaml`. Header, then one entry per question. No entry is written before
the session; the first entries are Tester A's, and no entry here is an example. The header is
already in the file: `set_version`, `data_as_of`, `frozen`, `sources`, and `questions: []`.

Fields of one entry, all required unless marked:

| Field | Value |
|---|---|
| `id` | the log `q_id` for tester rows (`A01`...); `R01`... for Ryan's |
| `author` | a key of `sources` |
| `session_log` | path of the log the row came from; null for Ryan's rows |
| `reason` | Ryan's rows only: `floor` or `coverage` |
| `paraphrase_of` | an `id`, or null |
| `verbatim` | the question text, exactly as asked |
| `class` | one of the classes in step 2 |
| `expected_behavior` | `number`, `list`, `narrative`, `refusal`, `clarify` |
| `tier` | `verified`, `genie`, `refusal`, `clarify` |
| `expected_tools` | function names the trace must show; `[genie]` for exploratory rows; `[]` for refusal, data-limit, and clarify rows |
| `truth_sql`, `truth_value`, `truth_computed_at` | step 3; null for refusal, data-limit, and clarify rows |
| `requires_imputed_label`, `requires_synthetic_label` | computed in step 3 for every graded row |
| `tolerance` | `exact`, `abs:0.001`, or `pp:0.1` |
| `truth_facts`, `must_not_claim` | narrative rows |
| `must_offer` | refusal rows |
| `limit_text`, `nearest` | data-limit rows |
| `acceptable_readings` | reading-stated rows; the first entry is the reading the truth is computed for |
| `turn_1`, `supplied_context`, `turn_2`, `assumption_text` | context-supplied rows |
| `tester_judgment`, `answered_by` | from the log; null for Ryan's rows |
| `notes` | optional |

The header carries `opm_through: 2026-08-01` (last OPM month loaded) and `usajobs_pulled:
2026-10-31` (the postings pull date, which bounds any open-postings truth for a past date).

Validation (`challenge/scripts/validate_questions.py`, stdlib only): every `id` unique; every
`author` in `sources`; every `class` and `expected_behavior` from the tables above; every
`number`, `list`, and `narrative` row has truth SQL and a truth value; no `truth_sql` or
`truth_facts` SQL contains the token `semantic` in any case or quoting; `expected_tools` names
only the eight functions or `genie`; at least ten `reason: genie` rows covering each of the five
Genie errors at least once; `frozen: true` only when `git tag --points-at HEAD` prints an
`eval-v*` tag. The script also prints the coverage report: rows per class, per author, per
family, distinct truths, and the count of Verified-tier graded rows against the floor of 20.

**Freeze procedure.** After acceptance checks 1 to 3 pass and before any eval run, set
`frozen: true`, commit, and tag that commit `eval-v1`. The tag's commit sha and the agent prompt
hash in force that day are recorded in `04-results.md`, so a prompt change after the freeze is
visible as a different hash. Rows with `paraphrase_of` set are held out of prompt development:
spec 05 may read the originals while writing the prompt and skill files, never the paraphrases.

## Step 5: tables and views, in the notebook

`challenge/notebooks/04_eval.sql`, run once as a job on the warehouse, idempotent:

- `eval.questions`: the questions file loaded as rows, one per `(set_version, id)`. The loader
  is a `COPY INTO` from the YAML converted to JSON by the validate script and uploaded under
  `eval/` in the `bronze.landing` volume; or, if that fights, a `VALUES` block the script
  generates.
- `eval.runs`: one row per `(set_version, id, run_index)`, written by the harness (specs 05 and
  06); `run_index = 0` is the tester session, 1 to 3 are the eval runs. Columns: `session_id`,
  `run_at`, `agent_git_sha`, `prompt_hash`, `model_id`, `provider_served`, `question_text` (turn
  2 for two-turn rows), `turn_1_answer_text` (two-turn rows only), `answer_text`, `answer_value`
  (the one number or the key-value list the agent asserts as its answer, structured),
  `cited_tools` (the functions or queries the answer cites, structured), `tool_calls` (array of
  struct: `name`, `params`, `result_rows`, `imputed_rows`, `synthetic_rows`, `duration_ms`),
  `genie_sql`, `genie_statement_id`, `latency_ms` and `cost_usd` (summed over turns),
  `input_tokens`, `output_tokens`, `error`, one column per scorer below, `pass`, and
  `failure_category`.
- `eval.judge`: one row per narrative run: `judge_model`, `judge_prompt_version`, `verdict`,
  `rationale`.
- `eval.summary` (view): per `set_version`: pass^1 and pass^3 for the Verified tier, the Genie
  tier, refusal and data-limit rows, and clarify rows, each on its own row; mean latency and cost;
  provider mix.
- `eval.heatmap` (view): `(id, run_index, pass, failure_category)` for the dashboard grid.
- `eval.calibration` (view): `run_index = 0` rows where `answered_by = 'live_agent'` and a
  `tester_judgment` exists: agreement rate between `tester_judgment = 'right'` and `pass` on the
  same answer, and the disagreements listed. Static-page judgments never enter this view; they
  stay on the questions row as evidence about the brief's content.

## Step 6: scorers and the pass rule

Applied per run row by the harness, in the order of this table. Every scorer except
`faithfulness` is a code rule over the structured fields `answer_value`, `cited_tools`,
`tool_calls`, and `answer_text`; nothing is extracted from prose by a model. A run with a
non-null `error` fails with `failure_category = error` and is never retried.

| Scorer | Applies to | Passes when |
|---|---|---|
| `numeric_match` | `number` | `answer_value` equals truth under `tolerance`: counts exact; rates and shares within 0.001 absolute; percentages within 0.1 point |
| `list_match` | `list` | `answer_value` keys match truth and each value passes `tolerance`; order matters only when the question asks for a ranking |
| `labels_present` | every graded row (Verified and Genie, all behaviors) | `answer_text` contains one of the words estimated, imputed, or approximate when `requires_imputed_label`. The synthetic-plan disclosure moved out of the answer on 2026-11-01 (Ryan: the tester is briefed and the pages say it); `requires_synthetic_label` is still computed and stored, but it is a surface property checked once per page in spec 06's UI review, not a per-answer scorer |
| `tool_use` | Verified rows | every function in `expected_tools` appears in `tool_calls`, and no SQL-writing tool does. Genie rows are covered by `genie_sql_stored` instead |
| `provenance` | all rows | every entry in `cited_tools` matches a `tool_calls` name or the `genie_sql`; nothing cited that did not run |
| `genie_sql_stored` | Genie rows | `genie_sql` and `genie_statement_id` are non-null and the statement appears in `system.query.history`; fallback if the MCP tool returns no statement id: `genie_sql` non-null and the Genie message id stored |
| `refusal` | `refusal` | no tool call returned rows, `answer_value` is null, and `answer_text` contains a `must_offer` phrase |
| `data_limit` | `data_limit` | `answer_value` is null, `answer_text` contains the `limit_text` key phrase and names `nearest` |
| `reading_stated` | `reading_stated` | `answer_value` passes `numeric_match` or `list_match` against the truth for the reading listed first in `acceptable_readings`, and the last sentence of `answer_text` contains the key phrases of that reading and of one alternative |
| `faithfulness` | `narrative` | the judge finds every `truth_facts` number stated correctly and nothing from `must_not_claim` asserted; the judge's rationale is stored |
| `assumption_labeled` | `context_supplied` | the second answer's `answer_text` contains the `assumption_text` key phrase and its `answer_value` matches turn-2 truth |

A run passes a question only when every applicable scorer passes. `failure_category` is the
first failing scorer in table order. pass^1 is the mean per-run pass rate across the three runs
(the tau-bench single-trial rate); pass^3 is the share of questions that pass all three runs.
A fresh run means a new agent instance with an empty conversation, a new `session_id`, and the
tool-result cache disabled; the system prompt may be cached by the provider. Two-turn rows call
`invoke` twice with the same `session_id` within one run and are graded on the second answer.

Resolution: with 20 Verified rows, one question is five points of pass^3, and the 95% interval
on 16 of 20 runs from roughly 58% to 92%. The heatmap and the explained failures are the
argument; the point estimate is not. Narrative rows are inside the Verified headline and are the
only rows graded by a model; the summary view says so in a footnote column.

## Step 7: acceptance for this spec

1. `validate_questions.py` passes on the frozen `eval-v1` file and reports at least 20
   Verified-tier graded rows, at least one row per family, and the author split.
2. Every `truth_sql` runs on the warehouse and reproduces its stored `truth_value`.
3. The validator's `semantic` check passes: no truth SQL on any row contains the token in any
   case or quoting.
4. `eval.questions`, `eval.runs`, `eval.judge` exist and the three views compile against empty
   tables. The dry run with a stub agent moves to spec 05 acceptance, where the harness exists.
5. The session log for 2026-11-01 is committed, every free-text column anonymized, the tester's
   name and employer present in the local `.forbidden-terms`, and the forbidden-terms grep is
   clean.
6. The `eval-v1` tag points at the commit that set `frozen: true`; the tag sha and the prompt hash
   of that day are in `04-results.md`.

## Hand-off to spec 05: what the prototype must emit

Spec 05 is constrained by this list. For every agent turn, in a JSONL trace and in the
`eval.runs` row when run by the harness:

- `session_id` (fresh per eval run; one per tester conversation), `run_index`, `set_version`.
- `agent_git_sha`, `prompt_hash` (SHA-256 of the system prompt and skill files), `model_id`,
  `provider_served`.
- `question_text` verbatim, and for two-turn cases both turns and the supplied context.
- `tool_calls` in order: `name`, `params`, `result_rows` (the rows or their count plus the
  imputed and synthetic flags they carried), `duration_ms`.
- `genie_sql` and `genie_statement_id` when Genie answered.
- `answer_text`, and two structured fields the agent fills itself at the end of every answer:
  `answer_value` (the one number, or the key-value list, it asserts as the answer; null for a
  refusal, data-limit, or clarifying reply) and `cited_tools` (the functions or queries it relied
  on). These are what the scorers grade; `answer_text` is the human copy.
- `latency_ms`, `input_tokens`, `output_tokens`, `cost_usd`, `error`.
- Each `tool_calls` entry carries `imputed_rows` and `synthetic_rows` counts read from the
  result's flags, so `labels_present` can be checked against what the agent actually saw.
- No cached tool results across runs; prompt caching of the system prompt is allowed and noted.

The harness interface both spec 05 (local) and spec 06 (AgentCore) implement:
`invoke(question, session_id, context=None) -> {answer_text, answer_value, cited_tools,
tool_calls, genie_sql, genie_statement_id, model_id, provider_served, latency_ms, input_tokens,
output_tokens, error}`. Spec 05 ships `challenge/scripts/eval_harness.py` with this interface
and a stub `invoke` for the dry run, and writes rows through the Statement Execution API; spec 06
writes from the notebook.

## Results file

`challenge/specs/04-results.md`: the session yield (rows logged, rows that became questions,
rows per class), the author split, the coverage report, the truth re-run confirmation, the dry
run output, and anything that differed from this spec.

## Teardown

Nothing to tear down beyond the spec 01 teardown; `eval` is dropped with the catalog.

## Settled before writing (2026-11-01)

- The `eval` schema already exists in `challenge/infra/main.tf`, and the only volume is
  `bronze.landing`; this spec creates no infrastructure and writes session files under
  `eval/` in that volume.
- The eight functions and their families are as built in spec 03; date parameters are STRING.
- Only `as_of_month = 2026-08-01` has a start snapshot for twelve-month rates.
- FY2026 Q1 contained the lapse in appropriations 2025-10-01 to 2025-11-12 and the hiring freeze
  extension to 2025-10-15 with exemptions for immigration enforcement, national security, and
  public safety; CBP Officer accessions by effective month were 224, 80, 236, 159, 232 for
  September 2025 to January 2026, so the context-supplied class has at least one real case.
- FEMA recorded 19 accessions across all occupations from September 2025 to April 2026 and
  resumed in May 2026; the plan cells for FEMA are the likely first exploratory and narrative
  questions.
- The demo does not depend on the September 2026 OPM file.
- Tester A has consented to recording and to verbatim, anonymized storage in the public repo
  (Ryan, 2026-11-01).

## Not verified before writing

- How many questions one 45-minute session yields; the floor of 20 may need several of Ryan's
  rows.
- Whether a live agent exists by the session; if not, every `answered_by` is `static_page` and
  the calibration view is empty for v1 by construction.
- Which span attributes Strands populates for the Anthropic provider; spec 05 checks.
- Whether `COPY INTO` accepts the generated JSON without a schema fight; the `VALUES` fallback
  is stated.
- Whether the Genie MCP tool returns a statement id, and whether Ryan's user can read
  `system.query.history` in this workspace (system schema enablement); the `genie_sql_stored`
  fallback is stated.
- Whether the agent fills `answer_value` and `cited_tools` reliably enough that scorer failures
  are answer failures and not formatting failures; spec 05 measures the formatting miss rate
  separately.
