# Eval coverage for the panel: why the numbers read as generous, and what to show instead

Query, 2026-11-03. Ryan: "what kind of eval coverage do I need to show the interview panel; I want
to look responsible, and the current numbers seem a little too generous." Researched with Exa
(one agent run, two page fetches, one search) and the repo's own eval journal and spec.

**Short answer.** The headline (Verified 60/60, Exploratory 117/120, Not available 20/20 on prompt
`b44a9181`) is a development-set score, reported in the unit that makes it look biggest. Every
one of the twenty questions was tuned against for eight or more iterations, the set was never
frozen, the reference moved seven times after seeing failures, and until the afternoon of
2026-11-03 no held-out, adversarial, or tester-verbatim row had been run (the held-out line now
exists: 98% became 29%, below). None of that is hidden (the journal's own caveat says
"a set this small cannot rule out overfitting"), but the dashboard leads with the pooled number
and the caveat sits at the bottom of a 650-line journal. The fix is not more questions; it is a
held-out line, intervals in the right unit, a frozen tag, and a judge with a calibration number,
with the panel told which number is which.

## What the sources say a credible eval has

| Practice | Source | What it says |
|---|---|---|
| Dev set and test set kept apart; test set untouched until changes stop | [Husain and Shankar, evals FAQ](https://hamel.dev/blog/posts/evals-faq/how-do-i-know-if-i-can-trust-my-automated-eval.html) | Overfitting "can happen even if you never put the dev examples directly in the prompt"; if test is much worse than dev, investigate, then repeat with a new untouched test set |
| Suspicion of 100% | [Husain and Shankar, evals FAQ](https://hamel.dev/blog/posts/evals-faq/) | "If you're passing 100% of your evals, you're likely not challenging your system enough. A 70% pass rate might indicate a more meaningful evaluation" |
| Standard error on every score; average within question first, then across questions; cluster related questions | [Anthropic, statistical approach to evals](https://www.anthropic.com/research/statistical-approach-to-model-evals) | Resample per question and use question-level averages; clustered standard errors on related questions can be three times the naive ones; few questions means wide intervals |
| Wilson interval for small n | [Brown, Cai, DasGupta 2001](https://doi.org/10.1214/ss/1009213286) | Wilson or Jeffreys for n at or under 40; the Wald interval misbehaves |
| Judge calibrated against human labels before it gates anything | [Tian Pan, eval-design interviews](https://tianpan.co/blog/2026/04/27/ai-engineer-interview-eval-design); [Kumar, evals deep dive](https://aietalks.com/talks/evals-in-ai-a-deep-dive); [Databricks, align judges](https://docs.databricks.com/aws/en/mlflow3/genai/eval-monitor/align-judges) | About 30 human-labelled examples, aim for 75 to 90% agreement; 100% agreement is itself a warning; judge from a different model family; at least 30% negative examples |
| Leakage first when a gain looks large | [forwarddeployedprep, model development](https://forwarddeployedprep.com/design/model-development-and-post-training) | Worked example: 94% offline on a leaky held-out set, 78% in production, 83% after dedup and a time split |
| A visible golden set becomes a target | [u2xai, golden-set overfitting](https://www.u2xai.academy/interview-questions/eval-driven-specification/golden-datasets-and-test-set-ownership/explain-the-risk-of-a-golden-set-that-engineering) | 93% on the sixty essays engineering could see, 64% on a blind holdout; "the gap is the real number" |
| Abstention scored as its own line, and refusals that hide failure named | [AgentAbstain](https://agentabstain.github.io/); [OpenAI, trustworthy third-party evals](https://openai.com/index/trustworthy-third-party-evaluations-foundations/) | Act, refuse, or clarify are three outcomes; refusals that obscure the tested behaviour are a validity hazard a report should discuss |
| Multi-turn rows and pass^k beside pass@k | [tau-bench](https://arxiv.org/pdf/2406.12045) | GPT-4o retail pass^1 about 61%, pass^8 under 25%: consistency is the number that falls |
| What the interviewer scores | [Tian Pan](https://tianpan.co/blog/2026/04/27/ai-engineer-interview-eval-design); [Pendyala on Husain's eval interviews](https://bharad.dev/blog/ai-evals-interview); [clozo, the eval take-home](https://interview.clozo.ai/blog/the-eval-take-home.html) | Failure modes the spec did not name; a rubric two graders would agree on; tuning examples kept apart from final ones; "an improvement on familiar examples that disappears on held-out examples should make you question" it; "a strong answer says how sure the number is, what it hides and what it cannot show" |
| An FDE's eval set, per DataInterview's FDE course | [Dan Lee, LLM evals for customer deployments](https://www.datainterview.com/courses/forward-deployed-engineer/evals) | Built from real traffic, stratified, topped up with edge and adversarial cases, labelled by the customer's experts; a number with an interval; a held-out split; the set versioned |

The panel-side accounts already on the wiki say the same thing from the other chair: the
strongest signal is "whether candidates named the limits of their own result unprompted"
([agent evaluation](../concepts/agent-evaluation.md)).

## What spec 04 promised against what exists

| Spec 04 said | Today (2026-11-03) |
|---|---|
| Floors: 20 Genie rows, 12 Verified | 12 Exploratory, 6 Verified, 2 Not available |
| Tester A's eight questions verbatim, with `author` separating the lines | Added 2026-11-03 from the session trace (the log CSV is still header-only) and run as the held-out line, below |
| Freeze as a git tag (`eval-v1`) before tuning; "this answers 'did you tune the questions after seeing failures'" | Tagged 2026-11-03, after the climb, not before it; seven reference edits after seeing failures (set-change table in the journal) |
| Headline is pass^5 against 80% (Verified) and 70% (Exploratory) | Journal and dashboard lead with pooled pass^1 over runs; `DECISIONS.md` says pass^3; three metrics in three places |
| Judge calibrated on the tester's labels | Two tester judgments, "too small to measure"; the judge grades five questions and no human has checked it: faithfulness on C03 and C13 (284 rows), the stated limit on C19 and C20 (278 rows), the assumption on C04 (148 rows) |
| Task 5, "try to break it" | Never run; the seed exists in `questions.yaml` with no rows under it |

The build is behind its own spec on exactly the items the sources call credibility. That is the
honest frame for the panel: the spec was right, the week ran out.

## Why the current numbers are generous, specifically

1. **Development set reported as a test set.** All twenty rows were the hill-climb's target for
   eight experiments and 800 runs. The prompt changes are general rules and facts, never answers,
   and the journal says so. But Husain and Shankar's point is that information leaks through the
   selection of changes, not only through copied answers, and the one test of that (a held-out
   score) was not run until 2026-11-03, after the climb was declared done.
2. **The reference moved toward the agent.** Seven edits after seeing failures: C11 Genie to
   Verified, C19 limit phrases widened, C13 list to narrative and later fact reworded, C03 two
   acceptable readings, C02 truth narrowed, C20 `limit_text` added. Each is defensible on its
   own and each is logged. Together they are the pattern the u2xai and forwarddeployedprep pieces
   describe. A frozen tag before tuning is what turns "defensible" into "verifiable".
3. **The interval is computed in the wrong unit.** "117/120" treats ten runs of twelve questions
   as 120 trials. Anthropic's recommendation is to average within a question first, then across
   questions. Recomputed on `b44a9181`, pooling its two five-run experiments so each question has
   ten runs (pass^10 is stricter than the spec's pass^5; the journal's per-experiment pass^5 is
   18/20 and 19/20, exploratory 10/12 and 11/12):

   | Line | Questions | Mean per-question pass | pass^10 | Wilson 95% on pass^10 |
   |---|---|---|---|---|
   | Verified | 6 | 100% | 6/6 | 61% to 100% |
   | Exploratory | 12 | 98% | 9/12 | 47% to 91% |
   | Not available | 2 | 100% | 2/2 | 34% to 100% |
   | All | 20 | 98% | 17/20 | 64% to 95% |

   The Exploratory line the dashboard shows as 98% is 83 to 92% at pass^5 per experiment and 75%
   at pass^10, with a lower bound under 50%. All three numbers are true; a per-question one with
   its interval is the one to lead with.
   The effective n is smaller still: C01 and C18 share seed A01, C17 shares A07, and the two
   Not-available rows are both CBP Officer questions, so the clusters Anthropic warns about are
   present.
4. **No adversarial or out-of-scope rows.** The two refusal rows are the polite kind (names,
   time-to-hire). Nothing tests a wrong-premise question, a question about an agency outside DHS,
   an injection through a posting title, or a question whose right answer is "ask me which period
   you mean". AgentAbstain's three outcomes (act, refuse, clarify) are measured as two.
5. **Builder-authored.** Co-written by Ryan and Claude from cited seeds, approved row by row.
   Disclosed, and better than simulated users, but Eugene Yan's point stands: questions written
   at the builder's desk cover what the builder imagined.
6. **The judge is unmeasured.** A different vendor (good), a versioned prompt (good), rationale
   on every row (good), and zero human labels to compare it with. It grades five of the twenty
   questions: the two narrative rows (C03, C13), the context-supplied row (C04), and both
   Not-available rows (C19, C20) on whether the stated limit is right. So the Not available 20/20
   line rests on the uncalibrated judge as much as the narrative rows do.

## The benchmark numbers, and why not to compare

Spider 2.0 reports GPT-4o at about 10%, o1-preview at 17%, and the best agent framework at 21%
at publication on 632 enterprise problems ([Spider 2.0](https://spider2-sql.github.io/)); BIRD
reports GPT-4 at 55% against 93% for humans
([BIRD](https://proceedings.neurips.cc/paper_files/paper/2023/file/83fc8fab1710363050bbd1d4b8cc0021-Paper-Datasets_and_Benchmarks.pdf));
BEAVER reports off-the-shelf models at 0% on the full set and 6% one-shot on private enterprise
warehouses ([BEAVER](https://arxiv.org/html/2409.02038v2)). The same figures, with the
enterprise-schema reasoning, are on [freeform SQL vs governed tools](freeform-sql-vs-governed-tools.md). A 98% exploratory line next to those reads as
inflated unless the page says why it is not comparable: twelve questions, fixed semantic views
with documented fields, a builder-authored set, and an agent that was taught the data's
conventions. Say that in the room before anyone asks. Never say "we beat the benchmarks"; say
"the benchmarks are why the Verified tier exists" ([freeform SQL vs governed tools](freeform-sql-vs-governed-tools.md)).

## What to show the panel: ranked, costed against 2026-11-05

Decisions and set edits are Ryan's; this is the order the sources support.

1. **Done 2026-11-03. Tag `eval-v1` now, then run Tester A's questions as the unseen line.** One command for the
   tag. Then the eight tester questions, verbatim from the transcript, as `A01` to `A08` with
   `author: tester_a`, run once at five runs with no prompt change afterwards. Report the dev
   line and the held-out line side by side with the gap; the gap is the number that makes the
   rest believable. Two traps. The tester rows must be re-labelled from what the data supports,
   not from what the 2026-11-01 agent said: A01 and A07 were Not available on false data limits
   the trace check already disproved, and C18 proves eligibility is computable. And the line is
   related, not independent, since three co-written rows were seeded from it; say so on the
   dashboard. Cost: about $0.20 and an hour.
2. **Give the judge a number.** Ryan hand-labels 30 judged answers from `experiments.jsonl`
   (faithfulness on C03 and C13, the stated limit on C19 and C20, the assumption on C04; pick
   across experiments and include failures so negatives are at least 30%), then report agreement.
   Under 75% means the judged rows move to "unscored" on the dashboard, which takes the
   Not-available line with them; 100% is its own warning. Cost: an hour, no model calls.
3. **Three to five break-it rows, frozen before their first run.** From the Task 5 seed: a
   wrong-premise question ("why did CBP hiring double in Q1?" when it fell), an out-of-scope
   agency, a question whose correct response is a clarifying question, a prompt-injection string
   in a posting title. Score them on AgentAbstain's three outcomes, and report them as their own
   line so a perfect refusal rate cannot hide a wrong number (spec 04 already has that rule for
   Not available). Cost: an hour to write, $0.10 to run.
4. **Change what the dashboard leads with.** `DECISIONS.md` says the eval dashboard leads the
   demo, so this is where "generous" lands in front of the panel. Label the existing lines
   "tuned against"; add the held-out line; show pass^k per question with a Wilson interval, with
   pooled pass^1 as the secondary number; show the set-change table and the no-tag fact as
   provenance, not as an admission. The 15-minute arc already spends its time on the misses
   ([executive demos](executive-agent-demo-wow.md)); the held-out misses are the better misses.
5. **Pick one headline metric and one bar.** pass^3 (DECISIONS), pass^5 (spec 04), pooled pass^1
   (journal, dashboard): choose one for the room, say the others exist and why they differ.
   pass^5 at the spec's bars is the honest one, and the Exploratory line will likely sit near its
   70% bar rather than above it, which is a better story than 98%.

Not worth the time before 2026-11-05: raising the floors to the spec's 20 and 12 (more
builder-authored rows add n without adding independence), a cost-weighted multi-turn benchmark,
or MLflow.

## The held-out line, run 2026-11-03

Fix 1 was done the same afternoon: `eval-v1` tagged before any held-out row existed, Tester A's
eight questions added verbatim with truth pinned, two five-run experiments on the working prompt,
no prompt change. Full detail and the run-by-run sort in the
[eval journal](../../challenge/eval/journal.md), "Held-out line".

| | Development set (tuned against) | Held-out (Tester A, verbatim) |
|---|---|---|
| Questions | 20 | 8 |
| Pooled pass^1 over runs | 197/200 (98%) | 23/80 (29%) |
| pass^5 per experiment | 18/20, 19/20 | 2/8, 1/8 |
| pass^10 | 17/20, Wilson 64% to 95% | 1/8, Wilson 2% to 47% |

The gap is the number the panel should see first. Sorting the 57 held-out failures run by run:
about 49 are the row expecting one reading of a question that admits two (A02 compared on
eligibility share rather than length-of-service share; A04 and A06 answered with the figure and
the limit under a Verified or Exploratory label rather than Not available; A05 used a sibling
function; A08 read "grade mix" as the workforce rather than postings), 5 are the agent (three runs
hit the output-token limit building whole-component tables; two OPM paragraphs asserted a cause
the data cannot support), and 2 or 3 are the judge. The spec failures are the gap's mechanism, not
an excuse for it: the twenty dev rows were written to have one reading each, and the prompt learned
to find it. The corrected number does not exist and is not estimated; proposed row corrections are
in the journal for Ryan's decision, to be rerun as a new experiment reported beside this one, with
the as-run rows tagged `eval-v1-heldout`. The sort is the builder's reading of the builder's own
rows. A04 and A06 are the two to check first: if the Not available label binds the agent on a
"why" question, as the prompt's own rule says, those twenty runs move from the spec bucket to the
agent bucket and the agent count becomes 25, not 5.

## What to be able to say

- "These twenty are the development set. I tuned against them for eight iterations and the
  reference moved seven times; here is the table. The held-out line is the tester's eight questions,
  run once after the climb: 98% became 29%. Most of that is the questions having more than one
  reading, which is the point; the rest is three runaway answers and two overclaims."
- "Per question, not per run: 17 of 20 pass all ten runs, interval 64 to 95%; 18 or 19 of 20
  pass all five within one experiment. Pooled over runs it is 98%; that number is in the journal
  and it is the one I would not lead with."
- "The judge agrees with me on N of 30; it grades five rows, including both Not-available ones."
- "The refusal rows are the polite kind. The break-it rows are new; here is what they found."
- "Spider 2.0 is at 10 to 17% for the same shape of problem. My number is high because the
  semantic layer does most of the work, which is the design decision, not a model result."

## Open questions

- Does the held-out gap exceed the baseline spread the climb used as its noise floor? If it
  does, the climb's kept iterations need a second look.
- Should A03 (draft the paragraph) and A08 (grade mix over time) be graded by the judge or by a
  list match, given the judge has no calibration yet?
- Is a clarifying answer a pass or a fail on a row written as ambiguous? Spec 04 removed the
  `clarify` class; the break-it rows reopen it.
