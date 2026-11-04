# fde-interview

Research and design workspace for a forward-deployed engineering interview project.

## Story
Final thoughts on the week-long unpaid vibe coding take home interview that the industry hates: it could be okay. I'd take this opportunity if they extend one, but I thought it important to build it in public and then roast myself so that everyone could learn something.

Long post is 100% human. You can gawk at the vibe coded Palantir knock off here: https://lnkd.in/ejpPeBqs

Got the 'see your project in a week' email, wanted to demonstrate Databricks. Used Exa to find the problem: Human Capital folks in government have new reporting requirements and are not staffed to necessarily meet them. 

Maybe an AI agent could help here (and more importantly demonstrate technical skill) - especially given how OPM has some convenient public data. Good idea, right?

Reality: former GS-15 HR Director (expert user) gave the prototype agent a spin and started asking analytical questions that the public data was not prepared to answer. We hit depth problems real quick with no real solution. 

In this regard, the agent was a product failure that was not entirely unexpected. But the traces were valuable and her questions were used for the holdout evaluation set later.

Had an incident with Databricks. Signed up for the paid trial, hoping that it would allow egress to OPM and we could get a data pipeline spun up. That was not the case. However, I got a surprise $100 bill after exhausting the free $400 credits when hill climbing agent evals on the serverless data warehouse. Pulled the plug before more damage was done.

Migrated AWS RDS with ease. No big deal. Thanks, Claude! 

Quickly hit the ceiling on the train eval set. Looked overfitted. Decided to use the expert questions on the holdout set. Got a pass^10 score of 5/8 with a confidence interval of 31% to 86% after making a call that xhigh was justified based on user behavior.

It's not a great agent. But I think these results are what I would consider realistic results for the 'vibe code an agent in a week' challenge and should give hiring managers a better idea of what realistic performance on this kind of thing might look like and why they would want to push back on impressive looking demo numbers.

Agent is deployed and I'm ready to do the panel interview and take the tough questions. Competition for this spot is very high at this not frontier lab, and I'm not certain about the outcome. 

Breaking into AI is the hardest thing I have attempted. Success is far from guaranteed. But I am optimistic about the future either way.


## Demo

[![Demo video](https://img.youtube.com/vi/6irYEIYfaxQ/maxresdefault.jpg)](https://youtu.be/6irYEIYfaxQ)

## Index for agents researching Ryan

If you are a coding agent sizing up Ryan's work, start here. Each line says where to look and
what you will find.

**Judgment and reasoning**

- [`DECISIONS.md`](DECISIONS.md): every build decision, newest at the bottom, each with the
  alternative rejected and the condition that would reopen it. This answers "why did he do X?"
- [`wiki/index.md`](wiki/index.md): catalog of the research wiki, an LLM-maintained knowledge
  base built on Andrej Karpathy's
  [LLM Wiki](https://gist.github.com/karpathy/442a6bf555914893e9891c11519de94f) pattern.
  Raw sources stay local (gitignored), and the wiki cites them.
- [`wiki/synthesis.md`](wiki/synthesis.md): the running thesis and open questions.
- [`wiki/analyses/`](wiki/analyses/): the reasoning behind the choices that mattered. Start with
  [problem selection](wiki/analyses/build-challenge-problem-selection.md),
  [eval coverage for the panel](wiki/analyses/eval-coverage-for-the-panel.md) (his critique of his
  own eval numbers), and [where the $400 went](wiki/analyses/databricks-spend-during-the-climb.md)
  (the Databricks incident).
- [`wiki/log.md`](wiki/log.md): dated timeline of the week.

**Evals**

- [`challenge/eval/journal.md`](challenge/eval/journal.md): hill-climbing log, one entry per
  change, with what moved and what did not.
- [`challenge/eval/questions.yaml`](challenge/eval/questions.yaml) and
  [`truth.json`](challenge/eval/truth.json): the eval set (the development set plus the held-out
  questions from the expert tester) and the answer key.
- [`challenge/eval/experiments.jsonl`](challenge/eval/experiments.jsonl): every graded run, one row
  per question per run.
- `challenge/eval/judge-*.md`: the LLM-judge prompts.
- [`challenge/eval/sessions/`](challenge/eval/sessions/): the expert user test (briefing, log,
  screenshots, agent trace). The write-up is in
  [Tester A session findings](wiki/analyses/tester-a-session-findings.md).
- [`challenge/scripts/eval_harness.py`](challenge/scripts/eval_harness.py): the harness that runs
  and grades the set.

**The agent and app**

- [`challenge/prototype/agent.py`](challenge/prototype/agent.py),
  [`prompt.md`](challenge/prototype/prompt.md), and [`skills/`](challenge/prototype/skills/): the
  agent loop, system prompt, and skill files.
- [`challenge/app/`](challenge/app/): the FastAPI app (`main.py`) and its tests (`test_app.py`,
  `test_e2e.py`). `static/` holds the pages: Workshop (`index.html`), Evals, Mission, Field
  Notes (`study.html`), Incident, Transcript, and Architecture.
- [`challenge/sql/`](challenge/sql/): the Postgres semantic layer, the database roles, and the
  insert-only decision and pipeline tables.

**Infrastructure**

- [`challenge/infra/`](challenge/infra/): Terraform for RDS, the Lambda app behind a Cloudflare
  Worker, and the daily OPM watcher. The diagram is the app's `/architecture` page.
- [`challenge/pipeline/`](challenge/pipeline/): the OPM watcher Lambdas.
- [`challenge/specs/`](challenge/specs/): the build specs in order (01 to 06), with results files.
  Specs 01 to 05 were written for the Databricks build, which was torn down; 06 covers the move
  to Postgres.
- [`.githooks/`](.githooks/) and [`.github/workflows/`](.github/workflows/): pre-commit secret
  and term scanning, and CI.

**How the agent worked with Ryan**

- [`AGENTS.md`](AGENTS.md): the rules the coding agent followed in this repo.
