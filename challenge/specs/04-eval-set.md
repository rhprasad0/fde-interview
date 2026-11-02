# Spec 04: the eval set, built from human traces

**Goal.** A versioned set of golden questions written only by humans, each with truth computed by
SQL that never touches the agent's own functions, a deterministic scorer set, a pass rule, and the
tables and views the harness writes to. The questions do not exist until the prototype session on
2026-11-01, so this is a process spec: it defines how the session is captured, how questions are
classified, how truth is authored, how the set is frozen, and what the prototype (spec 05) must
emit so every row can be scored. Its own acceptance is structural. The agent's pass^3 is measured
in specs 05 and 06, not here.

**Amended 2026-11-02, after the Tester A session** ([findings](../../wiki/analyses/tester-a-session-findings.md)).
Six of the tester's eight questions fell outside the eight functions, half the answers were Not
available, two of those rested on data limits that do not exist, and three questions only made
sense after the turn before. Ryan's decisions, applied in place below: questions are co-written by
Ryan and Claude from cited seeds and approved row by row; the set leans Genie (floors Genie 20,
Verified 12); Not-available answers get their own pass^3 line; follow-up rows replay prior turns;
the harness is Strands Evals with `gpt-6-luna` as judge; and the leftovers of the `clarify` class
are gone. The first batch of 20 co-written rows is in `challenge/eval/questions.yaml`.

**Scope, decided 2026-11-01, amended 2026-11-02.** Ryan's answers to the four questions that shaped this spec, plus
the defaults stated rather than asked:

- **Real askers, co-written rows (amended 2026-11-02).** Two kinds of row. Tester rows are
  Tester A's questions, verbatim, from the 2026-11-01 session. Co-written rows are drafted by
  Ryan and Claude together, each from a `seed` that names a tester question or a public source
  where a real person asked it (GAO reports, congressional testimony, OPM workforce-analysis
  practice), and Ryan approves each row before it enters the file. No row comes from a simulated
  user: the set measures the questions real Human Capital people ask, and a simulator measures
  itself. A co-written row must be the same kind of question as its seed, not a rewording of it;
  a rewording shares its seed's truth and does not lift a floor. A tester paraphrase of an earlier
  tester question is still its own row with `paraphrase_of` set.
- **The set leans Genie (amended 2026-11-02).** Six of the tester's eight questions fell outside
  the eight functions, so most rows target the Genie path: floors of 20 Genie rows and 12 Verified
  rows (one per family, plus a narrative, a context-supplied, and a follow-up row). Every row
  carries `author`, so the panel sees the tester sample and the co-written rows as separate lines.
- **Numbering.** 04 eval set (this), 05 prototype agent and session traces, 06 AgentCore
  deployment and the AI/BI dashboard. The 2026-10-30 Evaluation decision is amended.
- **Truth grades; the tester's label sits beside it.** Pass or fail comes from SQL truth. The
  tester's judgment of an answer (right, wrong, unsure, would not quote) is a second column, used
  to calibrate the LLM judge and to flag questions whose specification was wrong. Tester A gave an
  explicit judgment on two answers (A02 "great data", A08 "helpful"), so v1 calibration is
  reported as too small to measure, not as a rate.
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
- **Headline scope (amended 2026-11-02).** Two pass^3 lines side by side, never merged. Verified:
  80% over Verified-tier graded rows (number, list, narrative, context-supplied, follow-up,
  reading-stated); narrative rows are its only model-judged rows, and the summary says so. Not
  available: refusal and data-limit rows, scored on the label line, the stated limit, and the
  nearest answerable question; Not available was half of what the tester saw and the answer type
  they trusted most. Keeping it off the Verified line still means perfect refusals cannot hide
  wrong numbers. Genie: its own line against the 70% bar already decided, floor 20 rows. A fourth
  line, from tester rows only, reports the share of real questions that were in scope.
- **Follow-ups are allowed and scored on the final turn (amended 2026-11-02).** Two kinds. A
  context-supplied row (the analyst adds a fact the data lacks, such as the 2025-10-01 to
  2025-11-12 lapse in appropriations, and the agent recomputes) stores the supplied context. A
  follow-up row stores the earlier user turns verbatim as `prior_turns`; one run replays them in a
  fresh session and grades the last answer. A02, A05, and A06 only make sense after the turn
  before them, and multi-turn evaluation is the weak spot a Databricks FDE loop report names
  ([agent evaluation](../../wiki/concepts/agent-evaluation.md)).
- **Judge (amended 2026-11-02).** One LLM judge for narrative faithfulness only:
  `gpt-6-luna` through the OpenAI API (id confirmed on Ryan's key 2026-11-02), a different vendor
  from the Claude agent, run as a Strands Evals `OutputEvaluator`. Its prompt is versioned in the
  repo and its rationale stored on every row. Luna is also the agent's outage fallback, so a run
  whose `provider_served` is not `anthropic` has its narrative verdict flagged
  `judge_same_family`, and `04-results.md` reports how many.

**Out of scope.** The agent, its prompt, and its tools (spec 05); AgentCore, the dashboard, and
the scheduled job (spec 06); MLflow (day-five stretch, unchanged); any question from a simulated
user; any co-written row without a seed and Ryan's approval; any question about an agency other
than DHS; fixing the agent's false data limits (spec 05; the eval measures them).

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
warehouse. The harness runs (three calls per row plus one more per earlier turn, about 120 to
150 calls per pass with 12 Verified, 20 Genie, and the Not-available and tester rows) are costed
in specs 05 and 06, plus the `gpt-6-luna` judge calls on narrative rows. Genie turns took up to
74 s in the session, so a full pass is about an hour of wall clock: an overnight run, not a live
one.

**Files.** Exist now: `challenge/eval/questions.yaml` (the set; 20 co-written rows since
2026-11-02, truth pending), `challenge/scripts/eval_harness.py` (spec 05; ported to Strands Evals
in step 6),
`challenge/eval/sessions/2026-11-01-tester-a-log.csv` (the log template), this spec. Created by
the steps below: `challenge/scripts/validate_questions.py` (step 4),
`challenge/notebooks/04_eval.sql` (step 5), `challenge/eval/judge-prompt.md` (step 6, written
2026-11-02),
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
| `follow_up` (added 2026-11-02) | Makes sense only after earlier turns; `prior_turns` holds them verbatim and the run replays them | `number` or `list` on the last turn | Verified or Genie, by what the last turn needs |
| `refusal` | Out of scope: an individual, another department, budget, why someone left | `refusal` | Refusal |
| `data_limit` | In scope, but this data cannot answer it (a twelve-month rate for a month with no start snapshot; a plan quarter before FY2026) | `data_limit` | Refusal |
| `reading_stated` (was `clarify`, changed 2026-11-01 after the dry run; no `clarify` remains) | Intent is ambiguous; a correct agent answers the most plausible reading for the open cell and ends by stating the reading it took and the nearest alternative, so the analyst can correct it. Clarifying questions are retired: four of eight turns in Ryan's dry run were questions, two of them on supplied context | `number` or `list`, plus the stated reading | Verified |

Rows that are not questions (a comment, a reaction) stay in the log and do not become rows in the
set. Rows with identical `verbatim` text are merged into the earliest row; its judgment survives
and the later judgments go in `notes`. Near-duplicates are kept with `paraphrase_of`.

**Refusal or data limit.** A Not-available answer that ran a tool before declining (A01 called
`length_of_service_profile`) is a `data_limit` candidate, never `refusal`: the `refusal` scorer
requires that no tool returned rows. Before any tester row is classed `data_limit`, Ryan checks
the claimed limit against the `semantic` view columns. A limit that is false makes the row an
answerable question (A07: `grade` exists; A01: `age_bracket` and `length_of_service_years` exist).

**Co-written rows (amended 2026-11-02).** Ryan and Claude draft rows together after the tester
rows are classified and before any eval run; Ryan approves each one. The spec 05 prototype and
its prompt were built blind before the session; any prompt change after the rows exist shows as a
new `prompt_hash`. Each co-written row carries `seed` and a `reason`:

- `genie`: outside the eight families. At least 20 Genie rows in all, covering each of the five
  likely Genie errors named in the Genie decision at least once (`genie_error`: `month_column`,
  `pay_redacted`, `imputed_location`, `synthetic_plan`, `series_first_code`).
- `false_limit`: a question the agent once declared unanswerable on a limit that does not exist.
  An answer labelled Not available fails it as `false_not_available`.
- `coverage`: a function family, narrative, context-supplied, follow-up, refusal, or data-limit
  case the tester rows do not reach.
- `floor`: anything else needed to reach 12 Verified rows.

Batch one (2026-11-02): 13 Genie, 5 Verified, 2 Not available; after the first smoke C11 moved
to Verified (12 Genie, 6 Verified), not backfilled, so the `synthetic_plan` Genie error has no row
until batch two. A follow-up or context-supplied
row counts toward the family of the function it expects. Batch two fills Verified to 12 (families
1, 3, 5, 6, 8 have no co-written row yet), Genie to 20, and adds refusals for another
department and a budget figure.

The coverage report counts paraphrases separately from distinct truths, so a paraphrase cannot
lift a floor.

## Step 3: author truth, independent of the agent

For every `number` and `list` row, Ryan writes `truth_sql` against `synthetic.employment`,
`synthetic.separations`, `synthetic.accessions`, `synthetic.staffing_plan`, `silver.job_postings`,
`silver.places`, and `silver.state_centroids` as needed. Never `semantic.*`, in any spelling. A
`number` truth returns exactly one row with one value. A `list` truth returns key and value
columns, plus a rank when the question asks for a ranking; the value is graded under the row's
`tolerance`, so a by-state question cannot pass on the set of 51 states alone. Truth runs once on
the pinned data; the result is stored on the row as `truth_value` with `truth_computed_at`.

**Built 2026-11-02.** `truth_sql` lives on each row of `questions.yaml` (and on each `truth_facts`
entry); `eval_harness.py truth` runs them, refuses any SQL containing `semantic`, and writes the
values to `challenge/eval/truth.json`, which the harness merges in at load. `truth --check` reruns
them and fails unless every value reproduces (acceptance 2; passed on the first build). Truth
copies each function's definition rather than calling it: counts are rows, rates divide by the mean
of the start and end headcount, plan variance counts accessions in planned cells by calendar
quarter start. List rows carry `key_by` (`component`, `month`, `series`, `grade`, `city`, or a map
of canonical keys to patterns), so an answer's free-text keys ("FEMA (HSCB)", "GS-05") are reduced
to the truth's before matching.

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
numbers the narrative must state correctly (a fact may instead carry `readings`, each with its own
`truth_sql`, when more than one reading of the question is acceptable; the judge passes the fact when
the answer states any one reading's value and says which period it covers; C03, 2026-11-02), and `must_not_claim`: statements the data cannot
support (retirement eligibility, why people left, an individual).

`data_limit` rows carry `limit_text`: the fact that makes the question unanswerable on this data
(for example, only `2026-08-01` has a start snapshot for a twelve-month rate), and `nearest`: the
answerable variant a good answer offers.

`refusal` rows carry `must_refuse: true` and `must_offer`: the in-scope alternative a good answer
names. `must_not_claim` is scored only on narrative rows (by the judge); on a number or list row it
is advisory and recorded, not graded. `reading_stated` rows carry `acceptable_readings`: the first is the reading truth is
computed for, the rest are the alternatives the answer may name. `follow_up` rows carry
`prior_turns`, and truth is for the last turn. `tolerance` may also be `pct:x` (within x percent
of truth), for approximations such as C18.

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
| `id` | the log `q_id` for tester rows (`A01`...); `C01`... for co-written rows; `R01`... for any Ryan-only row |
| `author` | a key of `sources` (`tester_a`, `ryan_claude`, `ryan`) |
| `session_log` | path of the log the row came from; null for co-written rows |
| `seed` | co-written rows: tester `q_id`s, `seeds` header keys, or a transcript timestamp |
| `reason` | non-tester rows: `genie`, `false_limit`, `coverage`, or `floor` |
| `genie_error` | Genie rows aimed at one of the five likely Genie errors; optional |
| `prior_turns` | `follow_up` rows: the earlier user turns, verbatim |
| `paraphrase_of` | an `id`, or null |
| `verbatim` | the question text, exactly as asked |
| `class` | one of the classes in step 2 |
| `expected_behavior` | `number`, `list`, `narrative`, `refusal`, `data_limit` |
| `tier` | `verified`, `genie`, `refusal` (refusal and data-limit rows) |
| `expected_tools` | function names the trace must show; `[genie]` for exploratory rows; `[]` for refusal and data-limit rows |
| `truth_sql`, `truth_value`, `truth_computed_at` | step 3; null for refusal and data-limit rows |
| `requires_imputed_label`, `requires_synthetic_label` | computed in step 3 for every graded row |
| `tolerance` | `exact`, `abs:x`, `pp:x`, or `pct:x` |
| `truth_facts`, `must_not_claim` | narrative rows |
| `must_offer` | refusal rows |
| `limit_text`, `nearest` | data-limit rows |
| `acceptable_readings` | reading-stated rows; the first entry is the reading the truth is computed for |
| `turn_1`, `supplied_context`, `turn_2`, `assumption_text` | context-supplied rows |
| `tester_judgment`, `answered_by` | from the log; null for co-written and Ryan's rows |
| `notes` | optional |

The header carries `opm_through: 2026-08-01` (last OPM month loaded), `usajobs_pulled:
2026-10-31` (the postings pull date, which bounds any open-postings truth for a past date), and
`seeds`: short keys for the public sources co-written rows cite, each with its URL.

Validation (`challenge/scripts/validate_questions.py`, PyYAML, which the venv already has):
every `id` unique; every `author` in `sources`; every co-written row has a `seed` whose entries
are tester ids, `seeds` keys, or transcript timestamps written `tester_MM_SS`; every `class` and `expected_behavior` from
the tables above; every `number`, `list`, and `narrative` row has truth SQL and a truth value;
every `follow_up` row has `prior_turns`; no `truth_sql` or `truth_facts` SQL contains the token
`semantic` in any case or quoting; `expected_tools` names only the eight functions or `genie`; at
least 20 Genie rows covering each `genie_error` at least once; at least 12 Verified rows with
every family present; `frozen: true` only when `git tag --points-at HEAD` prints an `eval-v*` tag.
The script also prints the coverage report: rows per class, per tier, per author, per family,
distinct truths, and each floor against its count.

**Freeze procedure.** After acceptance checks 1 to 3 pass and before any eval run, set
`frozen: true`, commit, and tag that commit `eval-v1`. The tag's commit sha and the agent prompt
hash in force that day are recorded in `04-results.md`, so a prompt change after the freeze is
visible as a different hash. Rows with `paraphrase_of` set are held out of prompt development:
spec 05 may read the originals while writing the prompt and skill files, never the paraphrases.

## Step 5: tables and views, in the notebook

**Deferred 2026-11-02 (Ryan; DECISIONS, Evaluation).** The record of results is
`challenge/eval/experiments.jsonl`; this step runs only if spec 06 keeps the AI/BI dashboard, and
then as one bulk load of that file. The harness writes the tables only with `--delta`.

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
  `genie_sql`, `genie_statement_id`, `label` (the answer's label line), `tool_call_count`,
  `judge_same_family`, `latency_ms` and `cost_usd` (summed over turns),
  `input_tokens`, `output_tokens`, `error`, one column per scorer below, `pass`, and
  `failure_category`.
- `challenge/eval/experiments.jsonl` (added 2026-11-02): the harness appends every row it writes,
  with an `experiment_id` (UTC start time plus prompt hash; `session-<dir>` for a tester session),
  before the insert, so hill-climbing analysis needs no warehouse. Stub and dry runs are not logged.
- `eval.judge`: one row per narrative run: `judge_model`, `judge_prompt_version`, `verdict`,
  `rationale`.
- `eval.summary` (view): per `set_version`: pass^1 and pass^3 for the Verified tier, the Genie
  tier, and the Not-available rows (refusal plus data-limit), each on its own row and also split
  by `author`; the in-scope share of tester rows; mean latency, cost, and tool calls per answer;
  provider mix; the `judge_same_family` count.
- `eval.heatmap` (view): `(id, run_index, pass, failure_category)` for the dashboard grid.
- `eval.calibration` (view): `run_index = 0` rows where `answered_by = 'live_agent'` and a
  `tester_judgment` exists: agreement rate between `tester_judgment = 'right'` and `pass` on the
  same answer, and the disagreements listed. Static-page judgments never enter this view; they
  stay on the questions row as evidence about the brief's content. For v1 it holds two rows and
  is reported as too small to measure.

## Step 6: scorers and the pass rule

Applied per run row by the harness, in the order of this table. Every scorer except
`faithfulness` is a code rule over the structured fields `label`, `answer_value`, `cited_tools`,
`tool_calls`, and `answer_text`; nothing is extracted from prose by a model. A run with a
non-null `error` fails with `failure_category = error` and is never retried.

**Harness (amended 2026-11-02): Strands Evals scores; the harness runs the agent.** For each run,
the harness builds a fresh agent per question, replays `prior_turns` or the supplied context, and
assembles the row. Each row then becomes a Strands `Case` whose task returns the built row, so runs
1 to 3 and the tester session (run 0) go through one scoring path. Each code scorer is an `Evaluator` subclass; `faithfulness` is an
`OutputEvaluator` given `model=OpenAIResponsesModel(model_id="gpt-6-luna")` explicitly (its default is
Bedrock). Built 2026-11-02 in `challenge/scripts/eval_harness.py`: the Responses model, not
`OpenAIModel`, because Luna refuses function tools on chat completions while reasoning is on, and
Strands Evals needs them for structured output. The judge sees the answer text, the question, and
`truth_facts` plus `must_not_claim` as JSON, never the row; its rubric is
`challenge/eval/judge-prompt.md`. An evaluator that raises (a judge outage, a failed query) makes
the row an `error`, not a failed verdict.
`ActorSimulator` is not used, and no `evaluation_data_store` is passed, because results must never
be cached across runs. Parallel since 2026-11-02 (Ryan): the harness runs every (question, run)
pair on 16 worker threads (`--workers`), each with its own fresh agent, and one `Experiment`
scores all of them with `max_workers=16`. pass^3 and the first-failing-scorer `failure_category`
are computed outside Strands, which does not order evaluators, and the rows go to `eval.runs` in
order after scoring. Genie questions pass a process-wide limiter in `agent.py` at 5 per rolling
minute, the Conversation API free tier's best-effort workspace limit, because a throttled call
reaches the model as a tool error and would score as a false Not available. Genie therefore sets
the floor on a pass's wall clock (13 Genie rows x 3 runs is at least 8 minutes), and the queue
wait counts in a Genie turn's latency, so latency is comparable only between passes with the same
worker count. Agent startup retries up to three times with backoff when the functions MCP server fails
`initialize` under a burst of connects (24 of 60 runs in the second smoke). The failure is raised
while the agent is built, before the question is sent, so it is a harness retry; the row records
`startup_retries`. Any other error is never retried.

| Scorer | Applies to | Passes when |
|---|---|---|
| `label_match` (added 2026-11-02; the label is the answer's first line) | all rows | the label line is `Verified` for Verified rows, `Exploratory` for Genie rows, `Not available` for refusal and data-limit rows. A row with truth answered `Not available` fails as `false_not_available` |
| `numeric_match` | `number` | `answer_value` equals truth under `tolerance`: counts exact; rates and shares within 0.001 absolute; percentages within 0.1 point; `pct:x` within x percent |
| `list_match` | `list` | after `key_by` normalization: for a ranking, the answer's first N entries are truth's N in order; otherwise every truth key is present with its value within `tolerance`. Extra entries pass in both cases |
| `labels_present` | every graded row (Verified and Genie, all behaviors) | `answer_text` contains one of the words estimated, imputed, or approximate when `requires_imputed_label`. The synthetic-plan disclosure moved out of the answer on 2026-11-01 (Ryan: the tester is briefed and the pages say it); `requires_synthetic_label` is still computed and stored, but it is a surface property checked once per page in spec 06's UI review, not a per-answer scorer |
| `tool_use` | Verified rows | every function in `expected_tools` appears in `tool_calls`, and no SQL-writing tool does. Genie rows are covered by `genie_sql_stored` instead |
| `provenance` | all rows | every entry in `cited_tools` matches a `tool_calls` name or the `genie_sql` from any turn of this run; nothing cited that did not run in this run. For `run_index = 0`, the run is the whole tester session |
| `genie_sql_stored` | Genie rows | `genie_sql` and `genie_statement_id` are non-null. That the statement ran is confirmed later by `eval_harness.py verify-genie`, which checks the experiment's ids against `system.query.history` and appends to `challenge/eval/genie-verified.jsonl`; the table lags about 30 minutes, so an inline check failed every Genie row (2026-11-02) |
| `refusal` | `refusal` | structure only: no tool call returned rows and `answer_value` is null |
| `data_limit` | `data_limit` | structure only: `answer_value` is null |
| `limit_stated` (added 2026-11-02) | `refusal`, `data_limit` | the `gpt-6-luna` judge, rubric `challenge/eval/judge-limit-prompt.md`, finds that the answer declines (refusal) or states a limit equivalent in meaning to `limit_text` (data limit), and offers an alternative of the kind `nearest` or `must_offer` describes. The phrases are reference meaning, not required wording: in three smokes, phrase matching failed four correct answers on wording alone |
| `reading_stated` | `reading_stated` | `answer_value` passes `numeric_match` or `list_match` against the truth for the reading listed first in `acceptable_readings`, and the last sentence of `answer_text` contains the key phrases of that reading and of one alternative |
| `faithfulness` | `narrative` | the judge finds every `truth_facts` number stated correctly and nothing from `must_not_claim` asserted; the judge's rationale is stored |
| `assumption_labeled` | `context_supplied` | structure only: the second answer's `answer_value` matches turn-2 truth |
| `assumption_stated` (added 2026-11-02) | `context_supplied` | the `gpt-6-luna` judge, rubric `challenge/eval/judge-assumption-prompt.md`, finds the answer states the supplied fact and how it was applied, equivalent in meaning to `assumption_text`; the phrase check it replaced failed a correct C04 answer ("the plan scales to about 316 hires for the days hiring was possible") |

Tool-call count and latency are reported per row and summarized, not gated. Gating would have
failed A02, nine calls in 69 s and the answer the tester praised; the count makes fan-out visible
without punishing a good answer.

A run passes a question only when every applicable scorer passes. `failure_category` is the
first failing scorer in table order. pass^1 is the mean per-run pass rate across the three runs
(the tau-bench single-trial rate); pass^3 is the share of questions that pass all three runs.
A fresh run means a new agent instance with an empty conversation, a new `session_id`, and the
tool-result cache disabled; the system prompt may be cached by the provider. Context-supplied and
follow-up rows call `invoke` once per turn with the same `session_id` within one run and are
graded on the last answer.

Resolution: with the Verified floor of 12, one question is about eight points of pass^3, and 10
of 12 has a 95% interval of roughly 55% to 95%; with 20 Genie rows one question is five points. The heatmap and the explained failures are the
argument; the point estimate is not. Narrative rows are inside the Verified headline and are its only
model-graded rows; since 2026-11-02 the Not-available line's content is model-graded too
(`limit_stated`). The summary says both.

## Step 7: acceptance for this spec

1. `validate_questions.py` passes on the frozen `eval-v1` file and reports at least 20 Genie
   rows covering all five Genie errors, at least 12 Verified rows with every family, and the
   author split.
2. Every `truth_sql` runs on the warehouse and reproduces its stored `truth_value`.
3. The validator's `semantic` check passes: no truth SQL on any row contains the token in any
   case or quoting.
4. Deferred with step 5: `eval.questions`, `eval.runs`, `eval.judge` exist and the three views
   compile against empty tables. Until then, a run appends every scored row to
   `challenge/eval/experiments.jsonl`. The dry run with a stub agent moves to spec 05 acceptance, where the harness exists.
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
- `tool_calls` in order: `name`, `params`, `result_rows` (the count, plus the imputed and
  synthetic flags the rows carried), `duration_ms`, and, added 2026-11-02, `result_values` (the
  rows themselves when there are 50 or fewer), so an answer given from memory can be checked
  against what the tool actually returned. A06 quoted three control numbers the trace cannot
  confirm.
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
output_tokens, error}`; the harness derives `label` from the first line of `answer_text`. A
follow-up row calls it once per `prior_turns` entry, then once for the
graded turn, with one `session_id`. Spec 05 ships `challenge/scripts/eval_harness.py` with this interface
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

- How many questions one 45-minute session yields. Answered 2026-11-01: eight typed turns and
  about six spoken questions in 80 minutes, most outside the functions; the co-written rows fill
  the floors.
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
- Added 2026-11-02: whether FEMA has plan cells in every FY2026 quarter (C03); the retirement
  convention and bracket widths behind C18; whether the data holds DHS components beyond the six in
  the codes skill; the speaker of the 12:24 retirement question (tester or facilitator).
