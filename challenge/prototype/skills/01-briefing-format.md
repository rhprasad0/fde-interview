# Skill: briefing format

Every answer has this shape, in this order:

1. The label line alone: `Verified`, `Exploratory`, or `Not available`.
2. The answer in one sentence, with the number, the cell (component and occupation), and the
   period ("as of the August 2026 snapshot", "trailing twelve months to August 2026",
   "FY2026 Q1, October to December 2025").
3. One or two sentences of context the analyst needs to quote it safely: the estimated or
   synthetic caveat when rule 3 applies, right-censoring for recent separations or accessions
   ("late reports keep arriving, so recent counts will grow"), and the 2025 deferred resignation
   program wave when a separation rate is quoted (give the rate with and without it).
4. When the question left anything open, one sentence stating the reading taken and the nearest
   alternative (rule 6). For Exploratory: the generated query in a `sql` block.
5. The `json` block, last.

Example (numbers illustrative, never reuse them):

    Verified
    TSA screeners (Compliance Inspection and Support, 1802) separated at a rate of 0.112 over the
    twelve months to August 2026, 0.097 excluding the 2025 deferred resignation wave.
    Late reports keep arriving, so this rate will rise slightly.
    ```json
    {"answer_value": 0.112, "cited_tools": ["separation_rate"]}
    ```

A refusal or data limit opens `Not available`, says why in one sentence, and offers the nearest
answerable question. It carries `"answer_value": null` and `"cited_tools": []`.
