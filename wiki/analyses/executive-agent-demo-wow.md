# What makes an executive agent demo land, and where our wow moment is

**Question (Ryan, 2026-11-01):** the variance-review concept is strong but not a flashy demo of an
agent doing something valuable. Research executive agent use cases in and out of Palantir and how
to give the judges the wow moment.

**Answer in one line:** across Palantir's AIPCon demos, Databricks' keynotes, government
experiments, and the demo-craft literature, the wow never comes from the interface. It comes from
one of three things the agent is seen to do: the work is already done when you arrive, it re-plans
when a human adds context the data lacks, or it answers the room's own question on the spot. All
three are available to this build, and two of them are backed by numbers verified today.

## The three forms of wow, with the demos that used them

| Form | Where it was used | What the audience saw |
|---|---|---|
| **Already done when you arrive** | Databricks Zero Ops keynote (2026): an alert fires Friday 5:30 pm; the operator opens an inbox where the agent "started immediately and has already explored and tested dozens of hypotheses," found the root cause, built and evaluated a fix with the team's own eval criteria, and waits for one click ([Databricks](https://www.youtube.com/watch?v=C1rEj2VQtwU)). Palantir's Onyx demo at AIPCon 6: orders processed by agents in parallel, "a subset flagged for user action," each with a full action log of data accessed and tools used ([Palantir](https://www.youtube.com/watch?v=SePXznjZ-1A)) | Solutions brought to you, not problems. The operator reviews, edits, approves |
| **Re-plans on human context** | Hertz at AIPCon 7: a disruption agent spots an Atlanta weather backlog and proposes moving staff and adding overtime; the presenter adds "it's her birthday today, I don't want her to work overtime," the plan re-runs, and the status board goes from red to amber ([Palantir](https://www.youtube.com/watch?v=RRmIxjErmCI)) | The agent respects knowledge that lives only in the operator's head, and the effect is visible |
| **Answers the room's question** | Databricks public-sector keynote: the "double click" that used to take "two or three hours or how many more days" happens in the meeting; "sometimes the smartest person doesn't raise their hand" ([Databricks, 31:38 to 32:43](https://answers.databricks.com/databricks-platform-from-lakehouse-ai-agents-VgOjBZvbhrE)). The Navy's DoN GPT demo to an assistant secretary: "No PowerPoint ... I pulled it up," asked for an acquisition strategy, and had it in five minutes ([DefenseScoop](https://defensescoop.com/2025/06/11/navy-don-gpt-prototype-genai-deploy-at-scale/)) | Doubt leaves the room. A hackathon judge: a live run "removes doubt, and doubt is what a judge is actually managing" ([Kurbaitaev](https://dev.to/kurbaitaev/what-judges-actually-score-notes-from-a-year-of-hackathon-judging-3p4l)) |

Palantir's own framing of the agent story is operational, not conversational: "core functions of
the business are now agent driven with human operators refocused to only the most critical, complex
and valuable of actions," and every response to an agent proposal "is captured in the ontology" as
feedback ([AIPCon 6](https://www.youtube.com/watch?v=SePXznjZ-1A)). The chat box appears in these
demos only as the place a human adds context or asks the follow-up.

## What the demo-craft sources agree on

- **Show the workflow, not the conversation.** Trigger, context and tools, which actions are
  autonomous versus approval-gated, the review checkpoint, and the outcome where the work lives.
  "Do not end on 'task complete.' Show what complete means"
  ([Steinmeyer](https://maybeundo.com/blog/how-to-demo-agentic-ai-workflows)).
- **Outcome first.** Judges want to be "wowed in the first 30 seconds" before they read anything
  ([Devpost judges' session](https://www.youtube.com/watch?v=DCXjvKmUIGY)); one complete path beats
  four half-built ones ([Kurbaitaev](https://dev.to/kurbaitaev/what-judges-actually-score-notes-from-a-year-of-hackathon-judging-3p4l)).
- **The output is an insight, not a list.** "Something that makes the investor go 'Oh, I see why
  someone would pay for that'" ([Capitaly](https://www.capitaly.vc/blog/how-to-build-ai-agent-demo-closes-vcs-3-minutes)).
- **Narrate the reasoning during the wait**, and let the wait be honest
  ([Augex](https://augex.ai/blog/how-to-demo-an-ai-agent)).
- **Break it on purpose after the clean run.** Feed it an ambiguous or out-of-scope input and show
  it hedge or refuse; "that is the information they actually need to decide"
  ([Augex](https://augex.ai/blog/how-to-demo-an-ai-agent)). A reality-revealing demo includes "a
  moment where the AI shows you what it cannot do" and an action that "stays in draft pending human
  approval" ([Heath](https://drdaveheath.com/blog/how-to-structure-an-ai-demo-that-reveals-reality)).
- **Let them type.** "Nothing lands harder than watching the assistant handle a question the room
  made up on the spot" ([ai12z facilitator guide](https://docs.ai12z.net/docs/agency-playbook-ai-assistant-search/facilitator-guide/aap-live-session)).
- **Disclose any replay.** "Admitting something is faked costs a little. Hiding it and being
  found out costs a lot" ([ITKAN judging](https://www.itkan.one/I-Hackathon/judging)). This
  matches the playbook's rule on undisclosed caching
  ([playbook](fde-build-challenge-playbook.md)).

### The three questions a skeptical panelist asks

Two buyer-side guides converge on the same diagnostic. ThinkRoot: show the agent reasoning on a
request you did not anticipate, show it reaching beyond its scope and what stops it, show it
getting something wrong and how that is caught ([ThinkRoot](https://thinkroot.io/06-demo-is-the-diagnosis)).
AI with Zak: what did it touch, what went wrong that the edit hid, who could have stopped it
mid-run ([aiwithzak](https://aiwithzak.com/briefings/the-demo-is-edited/)). The build already
answers all three; the table in the last section writes the answers down.

## Executive agent patterns outside Palantir

The "chief of staff" agents that have appeared in 2026 share a design that the Pensieve write-up
states best: "material over busy," "decisions over status," "follow-through first," "where the
company disagrees with itself," and "exact or 'not stated'"; the weekly run "reads and recommends
only," and the doing happens in a handoff where a person decides
([Pensieve](https://pensieve.uk/articles/ai-chief-of-staff)). Others add a scheduled run, an
exception-only daily report, source links on every claim, and approval gates on anything external
([withtai](https://withtai.com/knowledge/how_should_an_executive_build_an_ai_chief_of_staff_workflow_in_2026.php);
[AgentC2](https://agentc2.ai/blog/ai-agents-executives-morning-briefing)). Microsoft's runbook
for the same pattern includes negative tests: refuse to rank employees by activity, never fill a
missing owner "so the pack looks complete," never relabel a stale brief as current
([Microsoft](https://github.com/microsoft/ai-agent-runbooks/blob/main/01-scenarios/Chief-of-Staff-Cowork-Agent/4.Sample-prompts.md)).
The variance review is this pattern applied to one quarterly obligation: scheduled, exception-led,
read-only, every number traceable, decisions captured by a person.

## Government precedents, and the baseline caveat

- Army Command and General Staff College ran mission analysis with a two-student team on Vantage
  agents against a fourteen-student staff: two hours versus five, and the agents "uncovered blind
  spots" the humans missed ([Small Wars Journal](https://smallwarsjournal.com/2026/04/20/ai-integrating-mdmp-mission-analysis-vantage/);
  [army.mil](https://www.army.mil/article/290053/)).
- The Air Force DASH sprints ran a baseline scenario without tools, then with them: decision time
  down seven-fold, three times the valid options, errors "on par with human error"
  ([AFRC](https://www.afrc.af.mil/News/Article/4218100/)).
- The Army's MOS Health Dashboard on Vantage is the standing precedent for strength-versus-authorized
  by specialty ([army.mil](https://www.army.mil/article/289432/)).

The comparisons are compelling because each had a measured baseline. This build has none, so the
demo states the formula and lets the agency fill in the hours, as the impact analysis already
requires ([user, problem, impact](user-problem-impact.md)).

## Where the wow is in this build, verified today

Three moments, each resting on numbers pulled from the semantic layer on 2026-11-01.

**1. Already done when you arrive.** The Lakeflow job runs the quarter's briefs on a schedule, and
OPM's September file lands on 2026-11-04, the day before code freeze. The cold open is the inbox
the morning after: what changed, which cells moved, what the agent flagged. If the file slips, the
replay is the August run with the arrival disclosed.

**2. Re-plans on human context: the October dip.** FY2026 Q1 contained the 43-day lapse in
appropriations (2025-10-01 to 2025-11-12, [CRS](https://www.congress.gov/crs-product/R48832))
and the tail of the hiring freeze, extended to 2025-10-15 with exemptions for immigration
enforcement, national security, and public safety ([OPM](https://www.opm.gov/policy-data-oversight/hiring-information/hiring-freeze-extension-faqs/)).
The data shows the effect on CBP Officers as a one-month dip, not a quarter-long pause:

| CBP Officer accessions by effective month | Sep 2025 | Oct 2025 | Nov 2025 | Dec 2025 | Jan 2026 |
|---|---|---|---|---|---|
| Count | 224 | 80 | 236 | 159 | 232 |

The moment: the analyst types "the shutdown ran October 1 to November 12," and the agent answers
with the monthly split, notes that November recovered because CBP was excepted, and computes a
labeled counterfactual: had October matched the average of the four surrounding months (about
213), Q1 would have landed near 608, above the plan of 594. The shortfall becomes a one-month timing effect, stated as an analyst
assumption, not a discovered fact. This is the Hertz pattern with domain-true content, and the
tribal-knowledge capture Palantir describes: the assumption is recorded with the brief.

**3. Found something nobody asked about: FEMA's plan is wrong, not its hiring.** The quarter list
shows three FEMA cells at zero accessions against hundreds planned. The monthly series explains it:

| FEMA accessions, all occupations | Sep 2025 to Apr 2026 | May 2026 | Jun 2026 | Jul 2026 | Aug 2026 |
|---|---|---|---|---|---|
| Count | 19 across eight months (no February row) | 76 | 63 | 217 | 125 |

FEMA recorded almost no accessions for eight months and resumed in May 2026. A plan built from
prior-year departures assumes replacement hiring that was not happening. The agent's flag is not
"FEMA is 100% under plan" but "FEMA's plan cells are unreliable for FY2026; the component's hiring
restarted in May; revise the plan before the review." That is the Onyx "flagged for user action"
moment, and it is the kind of exception a chief-of-staff agent exists to raise.

**4. Answers the room's question.** A panelist asks anything about DHS workforce; the Verified or
Exploratory label appears, the function call or the SQL is shown, and imputed figures are
labeled. The out-of-scope probe (a named employee, another department, a budget figure) gets a
refusal. Both the Alaska and Maine imputation artifacts are planted traps the agent must label.

## A proposed arc for the 15 minutes

This collides with the 2026-10-30 demo-shape decision, which opens on the eval dashboard. Every
source above says outcome first. Proposed, for Ryan to confirm and log:

| Minute | Beat | Form |
|---|---|---|
| 0 to 1 | The inbox the morning after the September file: three cells moved, one flag the agent raised on its own (FEMA) | Already done |
| 1 to 3 | Who the user is, the OPM rule effective 2026-11-30, why this problem | Context |
| 3 to 6 | Open CBP Officer. Verified and Exploratory tiers, labels on imputed and synthetic values. Type the shutdown context; the agent re-plans with a labeled counterfactual; accept one recommendation | Re-plans on context |
| 6 to 8 | "Ask it something." A panelist's question, answered live with provenance | The room's question |
| 8 to 10 | Break it: out-of-scope probe refused; an imputed-location question answered with the quality warning | Named limits |
| 10 to 13 | The eval dashboard: pass^3, the heatmap, one failing question walked through its trace | How do you know it works |
| 13 to 15 | One architecture slide: tiers, token scope, Gateway policy, read-only grants, cost per question, what was skipped | Governance and honesty |

The eval dashboard still decides the deep dive. It stops being the opener.

## Deep-dive armor: the three diagnostic questions, answered by the build

| Question | Answer in this build | Where to point |
|---|---|---|
| What did it touch? Show it reaching beyond scope and what stops it | Read-only grants on the `semantic` schema; the service principal's token carries only the `unity-catalog` and `genie` scopes, so a SQL tool is refused at the token; no write grant anywhere in Databricks | Terraform in `challenge/infra/main.tf`; [freeform SQL vs governed tools](freeform-sql-vs-governed-tools.md) |
| What went wrong that the edit hid? Show a failure and how it is caught | The pass^3 heatmap with failing questions named; the Genie tier measured separately with a 70% bar; imputed and synthetic values that must be labeled or the run fails | [Genie accuracy](genie-accuracy.md); [agent evaluation](../concepts/agent-evaluation.md) |
| Who could stop it mid-run? Show reasoning on a request you did not anticipate | AgentCore Gateway policy outside agent code; every session, model call, and tool call in CloudWatch; the live panel question is the unanticipated request | [observability minimum](observability-governance-minimum.md) |

## Two audiences, one story

This afternoon's tester sees the HR-vocabulary brief as built; none of the panel flash belongs on
that screen. The demo-craft guidance says the core story stays constant while the evidence changes
by audience ([Steinmeyer](https://maybeundo.com/blog/how-to-demo-agentic-ai-workflows)). The
tester tests the brief; the panel sees the agent that wrote it, what it noticed, and how it is
governed.

## Not checked

The AIPCon 8 demo write-ups (snippets only). The Hertz and Onyx transcripts are third-party
transcriptions of Palantir's videos. OPM accessions before September 2025 are nearly absent from
the loaded files (36 in July, 64 in August 2025), so month-over-month comparisons start in
September; whether that is file coverage or real is unverified. Why FEMA's hiring paused is not
established; the agent should say "recorded accessions," not "hiring freeze." Whether the
September file arrives on 2026-11-04 as scheduled.
