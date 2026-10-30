# Synthesis

The evolving thesis for the build challenge and the FDE interview. Updated on every ingest.

## Thesis (as of 2026-10-30)

1. **The panel is buying an FDE, not a demo.** The Firm's federal FDE program sells embedded
   engineers who go from ambiguous mission problem to working prototype in days, on whichever
   partner platform the client already owns ([program](entities/firm-federal-fde-program.md)). The
   build should look like a week-one FDE deliverable: a named user, a real decision, live data,
   governed access, and an honest account of trade-offs.
2. **Databricks is the right platform bet for Ryan specifically.** The program has a Databricks
   FDE track whose posting reads like a build checklist (Apps, Unity Catalog, Spark, LLM APIs), and
   the federal arm's public Databricks wins are "executive insight in days" stories. The agent
   layer sits above Databricks and calls OpenAI GPT directly, which mirrors how the Firm's clients
   appear to layer Palantir above Databricks and keeps the model portable to DoD environments
   ([analysis](analyses/build-challenge-problem-selection.md),
   [mission environments](analyses/databricks-in-mission-environments.md)).
3. **Federal workforce planning is the right problem.** OPM's 2026 open workforce API gives
   record-level monthly data with no auth, GAO has already analyzed the same files, and the 2025
   workforce shock makes the impact story current. The Firm has a (Palantir) posting in exactly this
   domain ([analysis](analyses/build-challenge-problem-selection.md)).
4. **Expect a Palantir-literate panel.** The program's partnerships and its student build event
   lean Foundry. Translate on the fly: Unity Catalog + Genie semantic layer for Ontology, UC
   functions for AIP Logic, Databricks Apps for Workshop.

5. **The eval set decides the deep dive.** Across FDE loops the differentiating question is "how
   do you know it works," and the artifacts that pass are a decision log, a small governed eval
   set with misses explained, a scripted failure path, and limits stated unprompted
   ([playbook](analyses/fde-build-challenge-playbook.md), [agent evaluation](concepts/agent-evaluation.md)).
   The Firm's prompt is near-verbatim Palantir's Build to Apply, so "why this problem" and "how
   you leveraged the platform" weigh as much as the code.

6. **The mandate is brand new and shaped like the demo.** OPM's final rule (published 2026-10-29,
   effective 2026-11-30) replaces HCOP, HRStat, and Human Capital Reviews with Annual Staffing
   Plans, quarterly staffing reviews, and quarterly variance explanations to OPM and OMB, for over
   80 agencies, produced by HR offices down 18.5% since December 2024. OPM's own FWD Chat answers
   plain-English questions over the public data, so the differentiation is cross-source, scheduled,
   governed, plan-aware briefings, not a chatbot
   ([user, problem, impact](analyses/user-problem-impact.md)).

## Open research questions

- Which Databricks previews (Managed MCP, Unity Gateway, Agent Bricks Supervisor) are available in
  a new AWS pay-as-you-go workspace in `us-east-1`, and what do they cost at demo scale?
- How does the Firm's FDE program evaluate build challenges? Any public write-ups from past
  candidates or from the student event?
- What does "forward-deployed engineering" mean at the Firm versus Palantir's original model? A
  concept page (`concepts/forward-deployed-engineering.md`) is still missing.
- Which frontier-lab partnership does the Firm's federal arm lean on most? The public
  announcements found so far are for OpenAI, Google, and Palantir.
