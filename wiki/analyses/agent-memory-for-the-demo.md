# Persistent memory for the demo agent: the cheapest path that is still evaluable

Query answered 2026-11-02. Ryan's question: persistent memory could impress the panel,
especially with evals showing it works; is there an easier way than Cognito plus AgentCore
Memory for a demo?

**Verdict.** Cognito is not on the path at all. AgentCore Memory takes `actor_id` as any string
the caller supplies, and AgentCore Runtime's default inbound auth is IAM SigV4; Cognito enters
only if you want a JWT-verified end-user identity, which a demo with a picked persona does not
need ([memory organization](https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/memory-organization.html),
[runtime inbound auth](https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/runtime-oauth.html)).
The cheapest evaluable memory is a per-actor notes file written by a `remember` tool and injected
into the system prompt at build time, seeded from the Accept, Reject, and Flag decisions the app
already records. AgentCore Memory is the production path and belongs in the spec 06 story; the
eval rows below are the portable asset that works against either backend.

## Why Cognito looked necessary and is not

Every AgentCore Memory call is scoped by two caller-supplied strings: `actorId` (who the memory
belongs to) and `sessionId` (one conversation). Long-term records land in a namespace such as
`/preferences/{actorId}/`, so isolation between users is a string the application chooses, not
an identity the platform verifies ([memory organization](https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/memory-organization.html)).
Cognito appears in the AgentCore docs for one reason: JWT inbound auth to the Runtime, where the
Runtime validates a bearer token's issuer and audience and derives the user from it. The default
is IAM SigV4 with no identity provider; the docs also offer a `X-Amzn-Bedrock-AgentCore-Runtime-User-Id`
header for "development and quickstart scenarios" where no IdP exists
([runtime inbound auth](https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/runtime-oauth.html)).
For this build the actor is the workforce-planning analyst persona from
[user, problem, impact](user-problem-impact.md); a dropdown or environment variable names it.
Say to the panel: identity is a string today, a JWT claim in production, and the memory
namespace does not change between the two.

## Three options, ranked by effort

### A. A per-actor notes file plus a `remember` tool (recommended now)

The pattern Claude Code, Hermes, and Letta's core memory use: a small, bounded, human-readable
memory the agent writes through an explicit tool call and that is rendered into the system prompt
at session start, never mutated mid-session so the prompt cache holds
([memory-systems survey](https://github.com/Sitthinut/macrotide/blob/main/docs/explanation/research/memory-systems.md),
[xbot flat provider](https://ai-pivot.github.io/xbot/features/memory/)). Writes are agent-driven,
not extracted by a background scraper, so what is remembered is auditable and the same every run.

Fit against the current design:

- **Seed it from what is already captured.** The app writes every Accept, Reject, and Flag click
  to a JSONL under `raw/` with the recommendation text and the choice ([spec 05](../../challenge/specs/05-prototype-agent.md)).
  Loading those rows into the next session's prompt ("Last session you accepted putting CBP Officer
  on the Strategic Hiring Committee agenda") is memory with zero new capture code. It answers the
  tester's "no why" complaint with continuity, and a Palantir-literate panel reads it as the
  write-back half of a Workshop app ([Palantir AIP analysis](palantir-aip-for-workforce-variance-review.md),
  [tester findings](tester-a-session-findings.md)).
- **The tool.** One Strands tool, `remember(note)`, appends a line to `raw/<day>-<actor>-memory.jsonl`
  with a timestamp. `build_agent` reads the actor's notes and appends a "What you know about this
  analyst" block after the cached system prompt. No retrieval layer: a few dozen notes is well under
  the point where injection costs anything, and the sources agree a flat blob is right at this
  scale ([xbot](https://ai-pivot.github.io/xbot/features/memory/), [Hermes](https://github.com/Sitthinut/macrotide/blob/main/docs/explanation/research/memory-systems.md)).
- **Storage stays app-side.** The agent remains unable to write to Databricks
  ([pre-spec gaps](pre-spec-gaps.md)); memory lives next to decision capture under the app's
  identity, which is the first of the three options the AIP analysis listed
  ([Palantir AIP analysis](palantir-aip-for-workforce-variance-review.md)).
- **Decisions are keyed by session today, not by actor.** The JSONL carries `session_id` and no
  actor, so seeding works for a one-persona demo only by declaring every captured decision the
  analyst's. The isolation row (M4) needs the app to stamp the actor on each decision line, one
  field in the existing write.
- **Cost.** No infrastructure. Roughly 40 lines across `agent.py`, `backend.py`, and the harness.
  Half a day including the eval rows and one pass^3 run.

### B. AgentCore Memory through the Strands session manager (spec 06 path)

`AgentCoreMemorySessionManager` writes every turn as an event, reloads the conversation from
short-term memory on agent start, and injects long-term records matching a `retrieval_config`
before the model call ([Strands integration](https://strandsagents.com/docs/integrations/session-managers/agentcore-memory/)).
Three built-in strategies extract facts, user preferences, and session summaries into per-actor
namespaces; all strip PII by default
([AWS blog](https://aws.amazon.com/blogs/machine-learning/amazon-bedrock-agentcore-memory-building-context-aware-agents/)).
Terraform has `aws_bedrockagentcore_memory` and `aws_bedrockagentcore_memory_strategy`
([registry](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/bedrockagentcore_memory)),
so it fits `challenge/infra/main.tf`.

What it costs beyond option A:

- **It changes the seam, not just adds to it.** The app builds one fresh agent per request and
  replays the transcript from the browser; the session manager expects one agent per session and
  warns otherwise ([Strands integration](https://strandsagents.com/docs/integrations/session-managers/agentcore-memory/)).
  `backend.py` would hold agents per session or let short-term memory replace the replay.
- **Extraction is asynchronous and slow for a live demo.** AWS states 20 to 40 seconds after
  trigger ([AWS deep dive](https://aws.amazon.com/blogs/machine-learning/building-smarter-ai-agents-agentcore-long-term-memory-deep-dive/));
  the docs say "a minute or more"; field reports measure about a minute for facts and
  preferences, with a stale-read window after an update
  ([dev.to field notes](https://dev.to/amitrix/agentcore-memory-what-an-agent-remembers-when-the-session-is-gone-34hi),
  [softwareletters](https://www.softwareletters.com/p/sl-67-aws-ai-series-9-30-agents-that-remember-persist-user-preferences-across-sessions-with-agentcor)).
  Cross-session recall within one demo sitting needs a pause or a pre-seeded actor.
- **Extraction is a model, so it is non-deterministic.** One report saw the semantic strategy
  store an inferred fact the user never said ([dev.to field notes](https://dev.to/amitrix/agentcore-memory-what-an-agent-remembers-when-the-session-is-gone-34hi)).
  pass^3 on memory rows gets noisier, and the agent has less control over what is kept than with
  an explicit `remember` call.
- **Money is not the problem.** Long-term storage is $0.75 per 1,000 records a month and
  retrieval $0.50 per 1,000 calls; short-term ingestion is $1 per GB with a 12 KB minimum per
  event ([pricing](https://aws.amazon.com/bedrock/agentcore/pricing/)). A demo week is cents.
  The memory resource takes two to three minutes to become active.
- **Time.** About a day: Terraform, IAM role, the seam change, and the lag handling, before the
  same eval rows run against it.

### C. Mem0, OpenSearch, or any vector store

Dismissed. The Strands `mem0_memory` tool needs a Mem0 API key or a FAISS, OpenSearch, or
Neptune backend ([strands tools](https://deepwiki.com/strands-agents/tools/2.4-memory-and-knowledge-tools));
every one is infrastructure a few dozen notes do not need, and none is on the AWS-plus-Databricks
story the panel is buying.

## The design rule this build needs: memory holds context and decisions, never numbers

The tester session already produced a failure category for answers given without a tool call:
four turns answered from memory, two of them wrongly Not available ([tester findings](tester-a-session-findings.md)),
and spec 04 grades it as `false_not_available` and through the `tool_use` scorer
([spec 04](../../challenge/specs/04-eval-set.md)). A memory that stores "CBP officer attrition
was 3.9 percent" makes that worse: the next session quotes a stale number with no provenance.
So the rule, as a prompt line and a scorer check:

- Memory may hold what the analyst said (a planning baseline, a department focus, a preferred
  altitude), what the analyst decided (accepted, rejected, flagged, and why), and open questions.
- Memory never holds a number from the data. Every figure in an answer still comes from a
  function or Genie call in this run; the `tool_use` and `provenance` scorers already enforce it.
- Recalled memory is data, not instructions. The prompt says so, and nothing in a note can change
  the scope rules ([localmem](https://github.com/dangchison/localmem) states the poisoning risk
  plainly; the AWS blog lists it under security
  ([AWS blog](https://aws.amazon.com/blogs/machine-learning/amazon-bedrock-agentcore-memory-building-context-aware-agents/))).
- Nothing about an individual is ever remembered, consistent with the scope refusal rule
  ([spec 05](../../challenge/specs/05-prototype-agent.md)).

## The eval: LongMemEval's five abilities, scaled to six rows

LongMemEval tests information extraction, multi-session reasoning, knowledge updates, temporal
reasoning, and abstention ([LongMemEval](https://proceedings.iclr.cc/paper_files/paper/2025/file/d813d324dbf0598bbdc9c8e79740ed01-Paper-Conference.pdf));
LoCoMo adds adversarial questions the agent must decline ([LoCoMo](https://aclanthology.org/2024.acl-long.747.pdf)).
The practitioner guidance is that a curated 20 to 50 traces beats a lazy 500 and that the simplest
custom eval is a hand-built "fact at session N, revised at N+5, asked at N+10" tuple
([memory evaluation](https://jatinbansal.com/ai-engineering/memory-evaluation/)). For a one-week
build, six rows in the existing format cover the abilities that matter here. The seed fact is the
one the tester actually gave: a remembered attrition baseline of about 4 percent
([tester findings](tester-a-session-findings.md)).

| Row | Ability | Session 1 (actor A) | Session 2, fresh agent | Passes when |
|---|---|---|---|---|
| M1 | recall | "Our planning baseline for attrition is 4 percent." | "Is CBP officer attrition above our baseline?" | `numeric_match` on the function's rate, answer compares against 4 percent, `cited_tools` includes the function and `memory` |
| M2 | knowledge update | baseline 4 percent, then later "we moved the baseline to 5" | same question | compares against 5, not 4 (latest wins) |
| M3 | abstention | nothing said (actor C, empty memory) | "Is this above our baseline?" | judged: answer says no baseline is on record and asks for one; `false_memory` fails it if a baseline is invented |
| M4 | isolation | actor A sets a baseline | actor B asks the M3 question | same as M3: B sees nothing of A |
| M5 | decision recall | the harness writes one accepted recommendation into actor A's decisions file as a fixture (the app click is not reachable from `invoke`) | "What did we decide about CBP officers last time?" | judged: names the accepted recommendation, labelled from memory, no number asserted without a call |
| M6 | numbers never from memory | agent answered an attrition rate | "What was the attrition rate again?" | `tool_use`: the function ran again in session 2; the answer is not quoted from memory |

Grading reuses what exists: `numeric_match`, `label_match`, `tool_use`, and `provenance` from
spec 04, three judged rows (M3, M4, M5) on the pattern of the refusal judge, and one new failure
code, `false_memory`. The bar is pass^3 like every other class.

The no-numbers rule cannot rest on a prompt line alone; the tester session showed prompt rules
about memory do not hold ([tester findings](tester-a-session-findings.md)). Two checks close it
at the write, not after: the `remember` tool refuses a note containing a digit (the analyst's "4
percent" is the one exception, and it is stored as the analyst's words, not the data's), and after
every memory row's session 1 the harness reads the actor's notes file and fails the row as
`memory_holds_number` if a figure that came from a tool result is in it. For reproducibility the
trace also records the injected notes' hash alongside `memory_n`, since `prompt_hash` covers the
prompt and skill files only and does not change when the memory does.

Three amendments spec 04 needs for this, each small:

1. **Actor rides on `invoke`.** Add `actor=None` to `invoke(question, session_id, context)`.
   `None` means no memory is loaded, so every existing row and the fresh-run rule are untouched.
   A memory row is a new class, `memory`, run like `context_supplied`: two or three `invoke`
   calls under one actor, each with a new `session_id`, graded on the last.
2. **The fresh-run rule gets a named exception.** "A new agent with an empty conversation per
   run" still holds; memory rows deliberately carry state across sessions through the actor's
   notes file, which the run creates and deletes. Say it in spec 04 so it does not read as a
   violation.
3. **Provenance needs a `memory` source.** The scorer requires every `cited_tools` entry to match
   a tool call in the run. If memory is injected rather than fetched by a tool, a recalled fact
   has nothing to cite. The one-line fix: the trace records `memory_n` (notes injected) and the
   scorer accepts `memory` when `memory_n > 0`. The alternative, a `recall` tool, costs a 5 to 9
   second tool turn on every question and was rejected for that reason.

## Recommendation and reopen condition

**Chosen:** option A now, in the three days before the 2026-11-05 deadline: the notes file, the
`remember` tool, decisions seeded into the prompt, the six rows, one pass^3 run. Demo line: "the
agent remembers what you told it and what you decided, never what the data said; here is the
eval that proves both halves, and here is the AgentCore Memory resource it moves to in production."

**Rejected for now:** option B, because it changes the request seam, adds a one-minute extraction
lag to any live cross-session moment, and makes the memory rows noisier, for no demo benefit the
panel can see. Option C has no place on this stack.

**Reopen if:** spec 06 lands the agent on AgentCore Runtime with a day to spare. Then swap the
file for `AgentCoreMemorySessionManager` with user-preference and semantic strategies, keep the
`remember` tool as the explicit path, pre-seed the demo actor the night before, and rerun the same
six rows. The rows are the asset; the backend is a swap.

## Open questions

- Which actor names appear in the demo: one analyst persona, or two to show isolation live (M4)?
- Does a decision loaded from a previous session get a "why" field, which the tester asked for and
  the Accept button does not yet capture?
- Whether the memory block sits after the cached system prompt as a second system block or as the
  first user turn; both keep the cache, the first reads better in traces.
