# Build cost estimate: Databricks on AWS plus AgentCore for one week

**Question (Ryan, 2026-10-30):** What does Lakebase cost, and what other Databricks costs will the
build challenge incur against the $50 budget?

**Answer in one line:** at list prices the Databricks side would run roughly $60 to $90 for the
week, but the business-email trial carries up to $400 of credits for 14 days, so Databricks should
cost nothing if the trial is started on day one. The AWS side (AgentCore, CloudWatch) is a few
dollars. The real risk is not rates but things left running.

All prices are AWS us-east-1, Premium tier, list, read 2026-10-30. Multiply DBUs by the SKU rate.

## Trial credits change the picture

- The Databricks trial offers "up to $400 in credits" valid for 14 days, no credit card needed to
  start, with a business email recommended to avoid trial limits ([try-databricks](https://www.databricks.com/try-databricks),
  [AWS Marketplace listing](https://aws.amazon.com/marketplace/pp/prodview-wtyi5lgtce6n6)).
- Adding a payment method at any time upgrades the account and removes trial limitations, and
  remaining credits still apply ([free trial doc](https://docs.databricks.com/aws/en/getting-started/free-trial)).
- One stale-looking line in the serverless SQL setup doc says the account "must not be on a free
  trial" ([setup doc](https://docs.databricks.com/aws/en/admin/sql/serverless)), while the trial
  doc lists a 50 DBU/hr cap on the trial's SQL warehouse. Treat as a conflict: if the warehouse
  will not start on day one, add the card and the question goes away.
- Databricks compute is covered by credits; AWS infrastructure outside Databricks is not. With an
  express serverless workspace there is no EC2, so AWS exposure is limited to AgentCore,
  CloudWatch, ECR, and any S3 you create yourself.

## Databricks line items

| Component | Rate | Week estimate at list | Lever |
|---|---|---|---|
| Serverless SQL warehouse, 2X-Small | 4 DBU/hr x $0.70 = $2.80/hr ([sizing](https://databricks.techfabric.com/guide/what-it-costs/)) | 15 active hours: ~$42. This is the biggest item. | Auto-stop at 5 to 10 minutes. Left on, it is $67/day. |
| Serverless generic compute for UC function tools | Unity Catalog functions called as agent tools run on serverless generic compute (Spark Connect), not the SQL warehouse ([create agent tools](https://learn.microsoft.com/en-us/azure/databricks/generative-ai/agent-framework/create-custom-tool)) | A few dollars for 75-run eval passes; confirm the SKU the MCP functions server bills to on day one | Keep functions small; the eval is the main consumer. |
| Serverless notebooks (dev) | $0.75/DBU, small session fee plus per-command compute | ~$10 to $20 for 20 dev hours | Close idle notebooks; charges stop after a few idle minutes. |
| Serverless jobs and Lakeflow pipelines (ingest) | $0.35/DBU ([CostAnalyst table](https://costanalyst.ai/blog/databricks-serverless-pricing)) | ~$5 to $10 for ten runs over a few monthly files | Trigger on demand, not on a schedule. |
| Lakebase (stretch, write-backs) | $0.092/CU-hr list, 50% promo to 2027-01-31 so ~$0.046; storage $0.345/GB-month; synced-table pipelines billed as serverless pipelines ([cost guide](https://www.databricks.com/blog/practical-guide-cost-optimization-lakebase-postgres), [LakeSentry](https://lakesentry.io/blog/databricks-lakebase/)) | ~$1 to $3 if sized at 1 CU with scale-to-zero | The default project autoscales 8 to 16 CU with a 24-hour idle timeout. Set min 1 CU (or the smallest allowed) and a 5-minute timeout, or it is ~$9 to $18 per day. Scale-to-zero needs 32 CU or smaller. |
| Genie One and Genie Agents | Free for human users through 2027-01-31; service principals are billed ([Genie cost](https://docs.databricks.com/aws/en/genie/monitor-cost)) | $0 if the agent calls Genie with the user's identity over MCP | If the agent runs as a service principal, Genie usage is billed at the Serverless Real-Time Inference SKU. One more reason for on-behalf-of auth. |
| Genie Code | 150 free DBUs per user per month, then pay-as-you-go | $0 | Stay under the allowance. |
| `ai_query` batch step | Dropped 2026-10-30: AI Functions are not in the GovCloud boundary and the separations file already carries the category ([mission environments](databricks-in-mission-environments.md)) | $0 | None. |
| MLflow LLM judges (eval) | Billed as model-serving tokens for the judge model | ~$1 for 30 cases x 5 scorers x a few runs | Run evals in batches, not on every save. |
| Unity Gateway usage tracking | Billed per GB of logged payload (Azure lists 1.429 DBU/GB) ([usage tracking](https://docs.databricks.com/aws/en/ai-gateway/usage-tracking)) | Cents | None needed. |
| Databricks Apps | $0.75/DBU, medium 0.5 DBU/hr | $0, not in the plan | If one is created for a UI, stop it between rehearsals. |
| Default storage for an express workspace | Databricks-managed; small | Cents for a few GB | None needed. |

Databricks total at list: roughly $60 to $90 for the week. Against $400 of trial credits: $0.

## AWS line items

| Component | Rate | Week estimate | Note |
|---|---|---|---|
| AgentCore Runtime v2 microVM | $0.1276/vCPU-hr, $0.0169/GB-hr, CPU not billed during I/O wait, memory reclaimed after 120 s idle ([AgentCore pricing](https://aws.amazon.com/bedrock/agentcore/pricing/)) | Under $2 for a week of dev and demo sessions | 128 MB minimum memory billing; 1-second minimum. |
| AgentCore Gateway (if used for MCP fronting) | $0.005 per 1,000 invocations; tool indexing $0.02 per 100 tools/month | Cents | Optional; direct MCP to Databricks avoids it. |
| AgentCore Memory | $1.00/GB ingested, $0.20/GB retrieved, long-term $0.75 per 1,000 records/month | Cents | Only if used. |
| AgentCore Evaluations (built-in) | $0.0024 per 1,000 input tokens, $0.012 per 1,000 output tokens | Under $1 | Optional alongside MLflow. |
| AgentCore Observability | CloudWatch rates | $1 to $3 | Keep log retention short; delete log groups at teardown. |
| ECR image storage | Standard ECR | Cents | Direct code deploy bills at S3 Standard instead. |
| Anthropic API, primary | Claude Haiku 5.5 on Ryan's credits; prompt caching on | Not on the $50 Databricks budget | 75 agent runs per eval pass is the main consumer; cache the system prompt and tool schemas. |
| OpenAI API, fallback | GPT-6 Luna on Ryan's funded account, used only on Anthropic outages | Not on the budget | Set a monthly cap in the OpenAI console; the eval rows record which provider served each run. |

New AWS customers get up to $200 in Free Tier credits; an existing account likely does not.

## The two ways to blow $50

1. A serverless SQL warehouse left running overnight: $2.80/hr, so about $67/day at list. Set
   auto-stop to the minimum and check it before closing the laptop.
2. A Lakebase project at its defaults: 8 CU minimum and a 24-hour idle timeout. Shrink it the
   moment it is created, or skip Lakebase until the core demo is green.

Everything else is dollars, not tens of dollars.

## Budget controls to set on day one

- Databricks budget alert on the account (Budgets are GA) at $25 and $45.
- AWS Budgets alert at $10 and $25, since AgentCore and CloudWatch bill there.
- Query `system.billing.usage` once a day; it breaks spend down by SKU and product.

## Teardown checklist

Databricks: stop the warehouse, delete the Lakebase project, delete the workspace, remove the
payment method if one was added, then cancel the subscription so it does not convert to
pay-as-you-go. AWS: delete the AgentCore runtime and gateway, the ECR repository, CloudWatch log
groups, and any S3 bucket. Keep the eval dataset and traces exported first; they are the evidence
for the write-up.

## Not verified

- Whether the trial's serverless SQL warehouse starts without a payment method (the conflicting
  doc line above).
- The smallest Lakebase compute size allowed; the docs give the default range, not the floor.
- Whether Databricks-managed default storage in an express workspace is billed separately.
- Serverless notebook DBU consumption per hour; Databricks does not publish a fixed rate.
