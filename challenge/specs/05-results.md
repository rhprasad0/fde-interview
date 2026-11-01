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
