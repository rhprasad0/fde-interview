# Hill-climbing journal

The experiment log for improving the variance-review agent against the eval set
(`challenge/eval/questions.yaml`, truth in `truth.json`). One entry per change. Raw rows for every
run are in `experiments.jsonl` under the experiment id; `eval_harness.py pool <ids> --vs <ids>`
reproduces every comparison below.

## Rules of the climb

- **Comparison rule** (spec 04 step 6): a change is judged on pooled pass^1 per line over two
  experiments of five runs each, against the pooled baseline, and on the rows that failed every
  baseline run. One experiment's pass^5 is reported, never compared.
- **Noise.** Four baselines of the same prompt landed Genie pass^1 at 61%, 53%, 47%, and 55% per
  experiment (22/36, 19/36, 17/36, 33/60). A move under about 8 points on one line is not a result.
- **Keep or revert.** A change is kept when a line rises clearly beyond noise and no line falls
  beyond it. Otherwise it is reverted, and the journal says why.
- **No teaching to the test.** Prompt and skill edits state general facts about the data (fields,
  codes, limits) and general behavior. They never contain a truth value, a question's wording, or
  an answer to a specific row. The set has 20 questions, so this rule is the only guard against
  overfitting until the tester's own questions join as unseen rows.
- **Plateau.** The climb stops when two consecutive changes fail to beat noise on any line.
- What changes is the agent: `challenge/prototype/prompt.md` and `skills/`. Every change shows as a
  new prompt hash in the experiment id. The model (Claude Haiku 5.5), tools, and data stay fixed.

## Baseline: prompt `4f3bf1e2`

Experiments `20261102T193041Z`, `20261102T200924Z`, `20261102T202445Z` (three runs each) and
`20261102T204103Z` (five runs).

| Line | Pooled pass^1 | pass^5 (last) |
|---|---|---|
| Verified | 47/84 (56%) | 3/6 |
| Genie | 91/168 (54%) | 3/12 |
| Not available | 28/28 (100%) | 2/2 |

Always fail (0/14): C02, C11 (component lists stop at the six components in the codes skill; the
data has twelve with plan cells), C10, C16, C18 (Not available on fields the data has: city,
senior executives by pay plan, age bracket), C06 (Genie returns part of a two-number answer).
Always pass (14/14): C05, C08, C19, C20.

Diagnosis: the agent knows the data only through what the eight functions return and a six-row
codes table. Prompt rule 5 and the limits skill tell it not to call a tool "to discover a limit
you already know", and it generalizes that into limits it does not know (no city, no grade, no
age) and declines without a call.

## Iteration 1: prompt `4c87b672`, kept

**Hypothesis.** The always-fail rows come from what the agent believes about the data, not from
reasoning. Give it the facts: all twelve components, the fields the records hold, and a rule that
only listed limits are limits.

**Change.**
- `skills/02-codes.md`: all twelve components with staff and a plan (was six).
- New `skills/06-data-fields.md`: the fields the records hold beyond what the calculations return
  (city, grade and pay plan, age bracket, pay, categories, posting fields), and that a field
  missing from a calculation's result is not missing from the data.
- `prompt.md` rule 5: the only known limits are those in the limits skill; try a one-off query
  before declaring any other field missing. Rule 10: a breakdown across components may call a
  standard calculation once per component.

**Harness incident.** The first attempt lost both experiments: when a long run's MCP session had
already closed, `cleanup()` raised in a `finally` and discarded the finished row. Fixed (cleanup
failures are ignored once the answer is in hand) and rerun.

**Result.** `20261102T211645Z`, `20261102T212936Z`.

| Line | Pooled pass^1 | Baseline | Change | pass^5 (each run) |
|---|---|---|---|---|
| Verified | 39/60 (65%) | 47/84 (56%) | **+9** | 3/6, 3/6 |
| Genie | 73/120 (61%) | 91/168 (54%) | +7 | 4/12, 4/12 |
| Not available | 20/20 | 28/28 | 0 | 2/2, 2/2 |

Rows that moved: C16 0/14 to **8/10**, C18 0/14 to **5/10**, C10 0/14 to 2/10, C06 0/14 to 2/10,
C11 0/14 to 2/10 (all three false-limit rows came alive). Regressions: **C14 12/14 to 0/10**, C08
14/14 to 8/10. Cost $0.44 for 200 runs; tool calls per answer 1.4 to 3.5; median latency 44 s to
77 s.

**Why the regressions, and one set correction.**
- C14 is the new skill's fault: it listed separation categories as "retirement voluntary and early
  out", omitting `RETIREMENT - OTHER`. The agent now asks Genie for exactly those two, and every
  month comes back a few short (49 against 54). A wrong fact in a skill is worse than none.
- C08: the answer shows the monthly table, but its structured `answer_value` carries the 2,456
  total. Rule 8 does not say which to report when an answer has both.
- C11: seven of ten runs errored when the functions MCP session closed partway through a 36-call
  sequential fan-out (twelve components by three quarters). A session-lifetime limit, met by a
  long run.
- C02 now names all twelve components with correct values and still failed: it ranks the eight
  that missed plan correctly and orders the four that came in ahead differently. The question asks
  which components missed by the most, so the truth should rank the misses only; it ranked all
  twelve. **Set correction:** C02 truth now ranks components with a negative variance. The
  baseline fails under either truth (its lists stop at six components), so the comparison stands.

**Decision.** Kept: Verified beyond noise, Genie at the edge of it, three always-fail rows alive,
and both regressions traced to wording errors in this change rather than to its direction.

## Iteration 2: prompt `f947333c`, kept

**Hypothesis.** Iteration 1's two regressions came from its own wording: an incomplete category
list steered Genie's filter, and rule 8 did not say what `answer_value` holds when an answer has a
breakdown and a total. Fix both; also ask for per-component calls in one step to shorten fan-outs.

**Verified first.** In iteration 1, 8 of 10 C14 Genie queries filtered to exactly `RETIREMENT -
VOLUNTARY` and `RETIREMENT - EARLY OUT`, the skill's two words, against 3 of 24 before it.

**Change.**
- `skills/06-data-fields.md`: the separation categories exactly as the records spell them, and
  "a question about retirements means all three".
- `prompt.md` rule 8: a breakdown or a multi-figure question puts the full key-value list in
  `answer_value`, even when the prose also gives a total. Rule 10: per-component calls requested
  together in a single step.

**Result.** `20261102T214522Z`, `20261102T215835Z`, against iteration 1.

| Line | Pooled pass^1 | Iteration 1 | Change | Baseline | pass^5 (each run) |
|---|---|---|---|---|---|
| Verified | 46/60 (77%) | 39/60 (65%) | **+12** | 56% | 3/6, 4/6 |
| Genie | 93/120 (78%) | 73/120 (61%) | **+17** | 54% | 7/12, 9/12 |
| Not available | 20/20 | 20/20 | 0 | 100% | 2/2, 2/2 |

All rows passing every run: 12/20 and 15/20 (baseline 9/20). Fixed: C14 0/10 to **10/10**, C06
2/10 to **10/10**, C08 8/10 to 10/10, C13 6/10 to 9/10, C02 0/10 to 6/10 (corrected truth; see
iteration 1). Fell: C18 5/10 to 0/10, C15 6/10 to 2/10. Five errors (C11). Cost $0.45.

**What is left, read from the answers.**
- **C18** no longer says Not available. It answers with a floor of 8,005 (age 50 with 20 years)
  and a ceiling of "about 11,400", and puts the floor in `answer_value`. Truth (11,387) counts 25
  years at any age as well. The question does not state a convention, so this is ambiguity in
  the set, not an agent error. For Ryan.
- **C15**: 7 of 10 runs read "this year" as calendar 2026 (138); truth is the trailing twelve
  months (170). The answer states its reading. Ambiguity in the set; for Ryan.
- **C10**: Genie queried the **December 2025** snapshot, because the agent's question to Genie named
  no month: the wrong-month Genie error the set was built to catch, triggered by an
  underspecified request.
- **C02**: some runs key components by name only ("FEMA"), so the key cannot be matched; one ranked
  by percentage missed rather than hires missed.
- **C11**: three errors from the functions MCP session closing mid fan-out (asking for the calls
  in one step did not stop it), and mixed count and percentage answers.

**Decision.** Kept: both answer lines beyond noise, the largest gain of the climb so far.

## Iteration 3: prompt `6c5b037a`, kept

**Hypothesis.** The answers that still miss come from vague requests to Genie (C10 queried
December 2025 because the request named no month) and from loose structured output (component
keys without codes, variance as a percentage in one run and hires in the next).

**Change.** `prompt.md` rule 8: one key form (component "Name (CODE)", month YYYY-MM, series four
digits, grade number, "City, State"). Rule 10: every one-off query states its period and
population in full; with no period in the question, the latest snapshot for staff counts and the
twelve months to August 2026 for separations and accessions. New rule 11: a plan variance is in
hires, with the percentage in the prose.

**Result.** `20261102T221348Z`, `20261102T222654Z`, against iteration 2.

| Line | Pooled pass^1 | Iteration 2 | Change | Baseline | pass^5 (each run) |
|---|---|---|---|---|---|
| Verified | 50/60 (83%) | 46/60 (77%) | +6 | 56% | 5/6, 4/6 |
| Genie | 104/120 (87%) | 93/120 (78%) | **+9** | 54% | 10/12, 8/12 |
| Not available | 19/20 (95%) | 20/20 | -5 (one run) | 100% | 1/2, 2/2 |

All rows passing every run: 16/20 and 14/20. C10 4/10 to **9/10** (the explicit period ended the
wrong-month query), C15 2/10 to 6/10, C02 6/10 to 9/10, C01, C13, C17 to 10/10. Cost $0.48.

**What is left.**
- **C11** 1/10, nine errors. Asking for per-component calls together now fires about 45 calls at
  once (twelve components by three quarters, plus retries); 6 to 12 of them come back as errors
  from the functions MCP server, and a run whose last call failed is an error row.
- **C19** one run computed a 30-day proxy for time to hire instead of saying it cannot be
  measured: an over-reach from iteration 1's rule 5 ("try a one-off query first"). The missing
  link from a posting to a hire is in the data-fields skill's list of things the records lack,
  but not in the limits skill, which rule 5 names as the only list.
- **C18** 0/10 and **C15** 4 misses: ambiguity in the questions (see iteration 2). For Ryan.

**Decision.** Kept: Genie beyond noise, Verified up, the one Not-available miss explained.

## Iteration 4: prompt `b06cf68a`, kept

**Hypothesis.** C11's errors are a burst problem (about 45 concurrent calls to the functions
server), and C19's one proxy answer comes from a limit missing from the list rule 5 trusts.

**Change.** `skills/03-labels-and-limits.md`: no applicant records, no link from a posting to a
hire (so no time to hire, no applicants per posting), no budget data. `prompt.md` rule 10:
breakdown calls in batches of at most twelve, one quarter's calls at a time; the "together in a
single step" wording from iteration 2 removed.

**Result.** `20261102T224153Z`, `20261102T225444Z`, against iteration 3.

| Line | Pooled pass^1 | Iteration 3 | Change | Baseline | pass^5 (each run) |
|---|---|---|---|---|---|
| Verified | 60/60 (100%) | 50/60 (83%) | **+17** | 56% | 6/6, 6/6 |
| Genie | 100/120 (83%) | 104/120 (87%) | -4 (noise) | 54% | 9/12, 6/12 |
| Not available | 20/20 (100%) | 19/20 | +5 | 100% | 2/2, 2/2 |

Zero errors. **C11 1/10 to 10/10**, every run exactly 36 calls (twelve components by three
quarters). C19 back to 10/10. All rows passing every run: 17/20 and 14/20. Cost $0.42.

**What is left.** 20 failed runs: C18 10 and C15 4 (ambiguity in the questions; for Ryan), and six
single misses on Genie rows (C07 2, C06, C12, C13, C17), Genie's own run-to-run variance.

**Headroom.** If C18 and C15 stay as written, the Genie line's ceiling is about 100/120 plus C15's
passes. The headroom left on every line is now smaller than the noise (about 8 points), so a
change can no longer be shown to help on these 20 questions.

**Decision.** Kept: Verified beyond noise, Genie within it, no errors.

## Iteration 5: prompt `c0924a3a`, reverted

**Hypothesis.** Genie's remaining single misses come from loosely worded requests; writing each
one-off query as a specification (measure, counting rule, exact filter values, grouping, a total)
would steady them.

**Change.** `prompt.md` rule 10: write every one-off query as a specification.

**Result.** `20261102T230916Z`, `20261102T232229Z`, against iteration 4.

| Line | Pooled pass^1 | Iteration 4 | Change |
|---|---|---|---|
| Verified | 57/60 (95%) | 60/60 | -5 (noise) |
| Genie | 103/120 (86%) | 100/120 (83%) | +3 (noise) |
| Not available | 18/20 (90%) | 20/20 | -10 (two runs) |

**Read from the answers.** Two C20 refusals failed `limit_stated` although they decline correctly
and offer counts: the judge called "the records hold no names" unsupported because C20's row gave
no limit text to check it against (the same reason passed in 18 other runs). A gap in the set's
reference, not an agent error; **set fix:** C20 now carries its limit. Most remaining Genie misses
are the shape of `answer_value`, not the number: C12 and C07 report the right figure (889, 94)
inside a list of total plus breakdown when the question asks for one number, which iteration 2's
"more than one figure means a list" wording invites. One C07 query counted by reported month (84),
a true Genie error.

**Decision.** Reverted to iteration 4's prompt (`b06cf68a`): no line beat noise. First
non-improving change in a row.

**Process slip.** The revert first restored the prompt from the commit that carried iteration 5,
and iteration 6's edit landed on top of it in commit `40b7214`. A hash check caught it before any
run; the next commit restores iteration 4's prompt and applies only iteration 6's edit (verified
by diff). No experiment ran on the mixed prompt `9c28ad3a`.

## Iteration 6: prompt `8c1cc317`

**Hypothesis.** C12 and C07 fail on the shape of `answer_value`, not the number. Make the shape
follow the question: one number for a one-number question.

**Change.** `prompt.md` rule 8, on iteration 4's prompt: a question that asks for one number gets
that number even when the prose adds a breakdown; a breakdown or several named figures get the
list.

**Result.** `20261102T233710Z`, `20261102T235010Z`, against iteration 4.

| Line | Pooled pass^1 | Iteration 4 | Change |
|---|---|---|---|
| Verified | 58/60 (97%) | 60/60 | -3 (noise) |
| Genie | 109/120 (91%) | 100/120 (83%) | +7.5 (at the edge, under the 8-point bar) |
| Not available | 20/20 | 20/20 | 0 |

All rows 187/200, the best of the climb; rows passing every run 17/20 and 16/20; zero errors. The
targets moved: C07 8/10 to 10/10, C12 9/10 to 10/10, C06 and C13 to 10/10, C15 6/10 to 9/10.

**Decision.** Not kept under the rule set before the climb: +7.5 is inside the noise bar, so this
is the second change in a row that did not clearly beat noise. The working prompt stays at
iteration 4. Iteration 6 is the candidate to adopt (a mechanism-backed fix, its target rows all
moved, nothing fell beyond noise); adopting it is Ryan's call, ideally after one confirming run.

## Plateau, and where the climb ended

The climb stopped at the plateau rule: iterations 5 and 6 both failed to clear the noise bar.

| Prompt | Verified | Genie | Not available | Rows passing every run |
|---|---|---|---|---|
| Baseline `4f3bf1e2` (four experiments) | 47/84 (56%) | 91/168 (54%) | 28/28 | 8/20 to 10/20 |
| Iteration 1 `4c87b672` | 39/60 (65%) | 73/120 (61%) | 20/20 | 9/20, 9/20 |
| Iteration 2 `f947333c` | 46/60 (77%) | 93/120 (78%) | 20/20 | 12/20, 15/20 |
| Iteration 3 `6c5b037a` | 50/60 (83%) | 104/120 (87%) | 19/20 | 16/20, 14/20 |
| **Iteration 4 `b06cf68a` (kept)** | **60/60 (100%)** | **100/120 (83%)** | **20/20** | **17/20, 14/20** |
| Iteration 5 `c0924a3a` (reverted) | 57/60 | 103/120 | 18/20 | 13/20, 14/20 |
| Iteration 6 `8c1cc317` (candidate) | 58/60 | 109/120 (91%) | 20/20 | 17/20, 16/20 |

Iteration 4's 120 Genie statements are all in `system.query.history` (`verify-genie`, 60 of 60
for each experiment). The climb's agent calls cost $2.68 across 1,200 runs, before the judge's
OpenAI calls and warehouse time.

**What moved the agent, in order of effect.**
1. Knowledge of the data, not reasoning: all twelve components, the fields the records hold, and
   "only listed limits are limits" (iteration 1) ended the false Not available answers.
2. Exact vocabulary: spelling the separation categories as the records do (iteration 2). A skill
   that names a subset steers Genie to that subset.
3. Precise requests to Genie: naming the period and population (iteration 3) ended the
   wrong-month queries.
4. Respecting the tools' limits: batching calls at twelve (iteration 4) ended the MCP errors.

**For Ryan.**
- **The Genie bar.** The headline rule is pass^5: 80% Verified, 70% Genie, and under 70% the agent
  loses the Genie tool (DECISIONS, Genie measured). Iteration 4's pass^5 is Verified 6/6 and 6/6
  (clears 80%), Genie **9/12 and 6/12** (75% and 50%: one experiment clears 70%, the other does
  not), Not available 2/2. Pooled Genie pass^1 is 83%. The choice: move the bar, declare pass^5
  on twelve Genie questions too coarse to trigger removal (the baselines measured that noise), or
  remove the tool.
- **Iteration 6** (`8c1cc317`, Genie 91% pooled) is likely a real gain: the 8-point bar came from
  the spread of 36-run experiments, and these comparisons pool 120 runs against 120, where the
  same noise is smaller. To adopt it: `git show 6af9d9a:challenge/prototype/prompt.md >
  challenge/prototype/prompt.md`, run one more five-run experiment, and pool it with the two
  above.
- **C18** (0/10 in five of six iterations) is ambiguity in the question: it asks for "roughly" how
  many could retire without a convention; the agent answers a floor (age 50 with 20 years) and
  names a ceiling of about 11,400, which matches truth (11,387); truth also counts 25 years at any
  age. **C15** is partly the question ("this year") and partly the agent's reading of it: it rose
  from 2/10 to 6/10 to 9/10 as the period rules tightened. Accepting both readings, as C03 does,
  or rewording, would make both measurable.
- **The live app changed.** `app.py` loads the same prompt files, so the tester-facing agent now
  runs iteration 4, not the prompt Tester A used.

**Every change to the set, in one place.** The set was never frozen (`frozen: false`, no
`eval-v1` tag). No question's wording changed and no answer went into the prompt; each edit
corrects truth or the scorer's reference.

| When | Row | Edit | Why |
|---|---|---|---|
| After smoke one | C11 | Genie to Verified | the agent answered it correctly from the functions |
| After smoke one | C19 | limit phrases widened (later replaced by the judge) | a correct answer missed the phrases |
| Truth written | C13 | list to narrative on the direction | answers used means, medians, and bands |
| After baseline one | C03 | two acceptable readings | "this year" read either way is reasonable (Ryan) |
| Iteration 1 | C02 | truth ranks components that missed plan only | the question asks which missed |
| Iteration 5 | C20 | `limit_text` added | the judge had no reason to check against |

**Caveat on the numbers.** Twenty questions, written with the agent's builder, tuned against for
six iterations. The prompt changes are general rules and facts, never answers, but a set this
small cannot rule out overfitting. Tester A's verbatim questions are the next test, but they are
**related, not independent**: several co-written rows were seeded from them (C01 and C18 from A01,
C17 from A07), so they share topics with the set the prompt was tuned on.

# Genie direct: benchmarks in the space

A second measurement, built 2026-11-02 after the agent climb plateaued: the eval's Genie-tier
questions asked of Genie directly, through the space's own benchmarks, with no agent writing the
request. `challenge/scripts/genie_bench.py` (`sync`, `run`, `report`); results in
`challenge/eval/genie-bench.jsonl`, tagged with a space hash (the space configuration without its
benchmarks), so a change to the space shows as a new hash the way a prompt change does.

**Two graders.** Genie's own benchmark grader compares result sets exactly and fails correct
answers on format: a month as a DATE where truth has `yyyy-MM`, every city where truth keeps the
top ten, two figures as columns of one row. `genie_bench.py` therefore also grades Genie's returned
rows with the agent eval's scorers (`numeric_match`, `list_match` with `key_by`), forgiving only
format (which columns, long or wide, a rate as a percent), never values. Every verdict of the first
run was checked by hand; a self-check confirms a wrong value still fails.

**Baseline, space `3443cb4f` (as built in spec 03: no column values visible, no expressions, no
example SQL).**

| Run | Pass (eval scorers) | Genie's grader GOOD | Minutes |
|---|---|---|---|
| `20261103T001958Z` | 5/11 | 2/11 | about 4 |
| `20261103T002537Z` | 3/11 | 1/11 | 3.7 |
| Pooled | **8/22 (36%)** | 3/22 | |

Through the agent (iteration 4), the same Genie-tier questions pass 83% pooled. The gap is the
agent's precise requests; the space-side levers (`wiki/analyses/genie-accuracy-levers.md`) are how
to close it inside Genie. Real errors seen: C16 counts 225 FEMA "senior executives" (truth 44),
C09 finds no CBP Officer pay row, C17 divides by average monthly headcount, C14 groups by month
name, C08 once returned zeros, C06 once counted the wrong population (1,368 against 1,041).

**Noise.** 5/11 then 3/11 with nothing changed: compare space changes on at least three pooled runs.
