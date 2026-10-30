# Agent evaluation

A small, versioned set of test inputs with expected outcomes, run against the agent with scorers,
so that "does it work?" has a number behind it. In FDE interview loops this is the question that
most often decides the deep dive (see [playbook](../analyses/fde-build-challenge-playbook.md)).

## Why it matters in the interview

- OpenAI's FDE loop reportedly treats "How do you know your AI system is actually working?" as
  the deliberate differentiator; being vague about measurement is the common way to fail
  ([rungcode loop map](https://rungcode.io/loops/openai), several candidate reports).
- A Databricks FDE loop report names "how you measure whether a compound AI system works,
  including partial credit across multi-turn agent interactions" as the most common weak spot
  ([rungcode](https://rungcode.io/loops/databricks), one report).
- One hiring team describes a final interview where roughly a third of the time is on "the
  evaluation set that guards" the agent: how it was built, how big, what one case contains, the
  pass/fail rule, and why that is enough to ship
  ([Cruitbase case study](https://cruitbase.com/case-studies/hiring-forward-deployed-engineers)).
- An interviewer-side account: the strongest signal is "whether candidates named the limits of
  their own result unprompted," and whether each claim "has a test behind it"
  ([forwarddeployedprep](https://forwarddeployedprep.com/practice/leading-people)).

## Minimal version for a one-week build

1. Write 20 to 30 questions a real user would ask. Pair each with the expected answer, computed
   deterministically (for the workforce agent: SQL against the silver tables).
2. Store the set where it is governed and versioned. On Databricks, evaluation datasets live in
   Unity Catalog ([building evaluation datasets](https://docs.databricks.com/aws/en/mlflow3/genai/eval-monitor/build-eval-dataset)).
3. Run `mlflow.genai.evaluate()` with built-in scorers such as `Correctness`, `Guidelines`,
   `RetrievalGroundedness`, and `Safety`, plus one code-based scorer for exact numeric match
   ([evaluation harness](https://docs.databricks.com/aws/en/mlflow3/genai/eval-monitor/concepts/eval-harness),
   [scorers](https://docs.databricks.com/aws/en/mlflow3/genai/eval-monitor/concepts/scorers)).
4. Report the score as "n of N" with a plain definition, and spend the demo time on the misses.
   The misses are the most interesting part ([fdetimes guide](https://fdetimes.net/en/guides/fde-take-home-defend-every-decision/)).
5. Keep the same scorers for production monitoring; MLflow uses identical traces for both.

## What to be able to say in the deep dive

- How the set was built, by whom, and what one case looks like.
- The pass rule and why it is enough for this user.
- Which failures are model failures and which are data failures, from the traces.
- What the result does not prove (sample size, redacted fields, one month of data).

## Related

- [Multi-agent orchestration](multi-agent-orchestration.md)
- [Build challenge](build-challenge.md)
