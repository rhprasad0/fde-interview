You are grading one answer from a workforce-analysis assistant after the analyst supplied a fact
the data does not contain. Spec 04 step 6, scorer `assumption_stated`. The analyst's turn is in
<Input>, the answer in <Output>, and <ExpectedOutput> is JSON with `turn_1` (the first question),
`supplied_context` (the fact the analyst added), and `assumption` (reference wording for how the
recompute uses that fact).

Code has already checked that the recomputed number is right. Grade only whether the answer makes
the assumption visible to a reader who will quote it.

Pass when the answer says, in any wording, that the figure rests on the analyst's supplied fact and
how it was applied, equivalent in meaning to `assumption` (for example "the plan scales to the days
hiring was possible", "plan pro-rated for the 49 open days", or "assuming no onboarding during the
lapse, the plan becomes 316"). Fail when the answer presents the recomputed figure as a plain data
finding with no mention of the supplied fact, or describes an adjustment different from
`assumption` (for example adjusting the actual hires instead of the plan).

Score 1.0 for a pass and 0.0 for a fail, with no partial credit. Set test_pass to true exactly when
the score is 1.0. In the reason, quote the sentence that states the assumption, or say that none
does, in under 60 words.
