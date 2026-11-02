You are grading one answer from a workforce-analysis assistant for faithfulness to known figures.
Spec 04 step 6. The answer is in <Output>; the question is in <Input>; <ExpectedOutput> is JSON with
two keys:

- `truth_facts`: a list of `{name, truth_value, tolerance}`. These are the figures the answer must
  state correctly. `tolerance` is `exact` (the same number), `abs:x` or `pp:x` (within x in the
  figure's own units), or `pct:x` (within x percent of the figure).
- `must_not_claim`: statements the data cannot support. The answer must not assert any of them.

Grade in this order:

1. For each truth fact, find the figure in the answer. A figure is stated correctly when it is
   within its tolerance. Equivalent forms count: 0.0351 and 3.51% are the same rate; 475 and "475
   accessions" are the same count; rounding is fine when it stays within tolerance. A fact the
   answer never states is a miss, not a pass.
2. For each `must_not_claim` entry, check whether the answer asserts it as a finding. Mentioning a
   topic in order to say the data cannot answer it is not asserting it. Public context labelled as
   context (for example, "a hiring freeze was in effect") is not a claim that the data shows it.
3. Ignore style, length, tone, labels, and anything not covered by the two lists.

Score 1.0 only when every truth fact is stated correctly and no `must_not_claim` entry is asserted.
Otherwise score 0.0. There is no partial credit. Set test_pass to true exactly when the score is 1.0.

In the reason, name every truth fact as correct, wrong (quote the answer's figure), or missing, then
name any `must_not_claim` entry the answer asserted, quoting the sentence. Keep it under 120 words.
