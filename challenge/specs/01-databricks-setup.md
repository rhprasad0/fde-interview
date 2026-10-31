# Spec 01: Databricks on AWS, set up and ready for AgentCore

**Goal.** A Databricks workspace in `us-west-2`, on direct-signup trial credits, with Unity
Catalog laid out, a read-only service principal, the Managed MCP Servers preview on, and one
proof: an external MCP client authenticates as the service principal and calls one Unity Catalog
function, and records the three OAuth facts the AgentCore Gateway spec needs.

**Out of scope.** Lakeflow ingest; the Genie space (needs data); any AgentCore resource; AWS
Budgets for AgentCore; MLflow; the eval harness; the dashboard. Each gets its own spec.

**Implements.** Platform, MCP path, Domain model (read-only), Observability (`DECISIONS.md`,
2026-10-30); Signup, Region, Terraform (2026-10-31). Costs in [the cost estimate](../../wiki/analyses/build-cost-estimate.md).

**Identities.** Ryan's admin user does every step and owns the catalog. The Lakeflow job and the
eval notebook in later specs run as that same user, so no job identity, no secret-scope ACL, and
no write grant is created here. The service principal `workforce-agent` is the only other
identity and it only reads.

**Rule.** No workspace URL, account id, warehouse id, client id, or secret in any tracked file
(`AGENTS.md`). Real values go in `challenge/.env` (gitignored); commit only `challenge/example.env`.
Before pasting any console or script output into `01-results.md`, replace the host with
`<workspace>` and the application id with `<application-id>`.

**Budget.** Under $5 of trial credit. Nothing runs unattended.

## Step 1: sign up directly, confirm region and serverless

- **Why direct.** Express setup starts with only an email. With no payment method on file, access
  stops when the credits are used or expire, so the trial caps spend
  ([express setup](https://docs.databricks.com/aws/en/getting-started/express-setup)). An AWS
  Marketplace trial instead rolls to pay-as-you-go on the AWS account
  ([free trial](https://docs.databricks.com/aws/en/getting-started/free-trial)). The serverless
  workspace runs in Databricks' AWS account, so nothing touches Ryan's. Do not create a classic
  workspace; it provisions a VPC and NAT gateway that AWS bills directly.
- **Do.** [databricks.com/try-databricks](https://www.databricks.com/try-databricks), sign up with
  the business email, no payment method.
- **Region.** Express setup offered no choice and placed the workspace in `us-west-2`
  (2026-10-31). That is the build region for Databricks and AgentCore (`DECISIONS.md`).
- **Done when.** Manage trial shows the credit balance and the trial end date; the region is
  `us-west-2`; a new serverless notebook runs `print(1)`. The notebook check settles whether
  serverless notebooks and jobs work on this trial type, which the ingest and eval specs depend
  on. Record the workspace URL in `.env`.
- **Trial end.** Access stops at the end date unless a payment method is added. If the interview
  falls after it, add one (a card, or link the AWS account for billing) the day before.

## Step 2: budgets

- **Do.** Account console (workspace dropdown, Manage account), Usage, Budgets, Add budget. One
  budget, whole account, all resource types, two monthly thresholds at $25 and $45, email to Ryan.
  Budgets alert only, at list price, with up to 24 hours of lag
  ([budgets](https://docs.databricks.com/aws/en/admin/account-settings/budgets)).
- **Done when.** The budget shows both thresholds.

## Step 3: sign the CLI in and find the warehouse

Run steps 3, 4, and 8 in a shell that has not sourced `.env`: its `DATABRICKS_CLIENT_*` variables
would sign the CLI in as the read-only service principal.

```bash
databricks auth login --host <workspace-url> --profile workforce
databricks warehouses list -p workforce
```

- The workspace auto-creates a Starter Warehouse and the trial allows one
  ([SQL warehouse](https://docs.databricks.com/aws/en/compute/sql-warehouse)). Put its id in `.env`
  as `DATABRICKS_WAREHOUSE_ID`. If the list is empty, delete the `import` block in
  `challenge/infra/main.tf` and Terraform creates the one warehouse.
- **Done when.** The list prints and the id is in `.env`.

## Step 4: Terraform the workspace objects

`challenge/infra/main.tf` holds what the agent's governance depends on: the warehouse settings
(serverless, 2X-Small, auto-stop 5 minutes, one cluster), the `workforce` catalog and its four
commented schemas (`bronze`, `silver`, `semantic`, `eval`), the `workforce-agent` service
principal with the Databricks SQL access entitlement (Genie consumers need it later,
[Genie setup](https://docs.databricks.com/aws/en/genie/set-up)), its grants, and the `workforce`
secret scope. State stays local and gitignored; it holds the workspace URL and the application id.

The provider cannot create a catalog on default storage ("Metastore storage root URL does not
exist", 2026-10-31), so create it first in the SQL editor; `main.tf` imports it and ignores the
storage root and collation the server assigns.

```sql
CREATE CATALOG IF NOT EXISTS workforce COMMENT 'Federal workforce-risk briefing agent: OPM FWD and USAJOBS';
```

```bash
cd challenge/infra
terraform init
terraform apply -var "warehouse_id=<warehouse-id>"
terraform output agent_application_id     # into .env as DATABRICKS_CLIENT_ID
```

- **Grants.** Four privileges, no `SELECT`: `USE CATALOG` on `workforce`, `USE SCHEMA` on `silver`,
  `USE SCHEMA` and `EXECUTE` on `semantic`. `EXECUTE` on the schema covers every function in it,
  now and later, so `semantic` is the boundary of what the agent can call. It also lets Terraform
  run before the smoke function exists. Nothing on `bronze` or `eval`.
- **If the warehouse refuses to start,** add the payment method via Manage trial; credits survive
  ([conflict noted here](../../wiki/analyses/build-cost-estimate.md)).
- **Done when.** A second `terraform plan` reports no changes; `SELECT 1` runs on the warehouse
  and it stops after idle; and this query returns the four grants above and nothing else:

```sql
SELECT 'catalog' AS level, catalog_name AS object, privilege_type
FROM workforce.information_schema.catalog_privileges WHERE grantee = '<application-id>'
UNION ALL
SELECT 'schema', schema_name, privilege_type
FROM workforce.information_schema.schema_privileges WHERE grantee = '<application-id>';
```

## Step 5: smoke table and smoke function

```sql
USE CATALOG workforce;
CREATE TABLE IF NOT EXISTS silver.smoke (agency_code STRING, headcount INT);
INSERT INTO silver.smoke VALUES ('HS', 3), ('TR', 2);

CREATE OR REPLACE FUNCTION semantic.headcount_for(agency STRING)
RETURNS BIGINT
COMMENT 'Smoke test: headcount for one agency code from silver.smoke'
RETURN SELECT sum(headcount) FROM silver.smoke WHERE agency_code = agency;

SELECT semantic.headcount_for('HS');  -- expect 3
```

- **Done when.** Returns 3. The function is replaced in the semantic-layer spec.

## Step 6: the service principal's OAuth secret

- **Do.** Settings, Identity and access, Service principals, `workforce-agent`, Secrets, Generate
  secret. Lifetime 60 days, so it outlives an unscheduled interview. Scopes `unity-catalog` and
  `genie` only ([scopes](https://docs.databricks.com/api/workspace/scopes)); scopes are fixed at
  generation ([OAuth M2M](https://docs.databricks.com/aws/en/dev-tools/auth/oauth-m2m)). Copy the
  secret once into `.env`. This stays in the UI: the Terraform secret resource cannot set scopes
  and would write the secret into state.
- **Done when.** `.env` holds the client id and the secret.

## Step 7: enable Managed MCP Servers

- **Do.** Settings, Previews, enable Managed MCP Servers ([built-in MCPs](https://docs.databricks.com/aws/en/agents/mcp-tools/built-in-mcp-services)).
  Leave the Unity Gateway beta off; the chosen path does not use it.
- **Done when.** The preview shows On.

## Step 8: secret values for the USAJOBS key

Terraform created the scope; the values go in by CLI so they never reach state.

```bash
databricks secrets put-secret workforce usajobs_api_key -p workforce   # paste when prompted
databricks secrets put-secret workforce usajobs_email -p workforce
```

- **Done when.** `databricks secrets list-secrets workforce -p workforce` shows both keys.

## Step 9: acceptance test, the AgentCore handshake from a laptop

Three facts come out of this step and all three go into `01-results.md`: that the OAuth discovery
document is reachable (the Gateway's credential provider is configured from it), which client
authentication method and scope string the token endpoint accepted, and whether a schema-level
MCP URL works (one Gateway target per schema) or only per-function URLs (one target per function).

```bash
cd challenge && uv venv && source .venv/bin/activate && uv pip install mcp httpx python-dotenv
set -a; source .env; set +a
curl -s "$DATABRICKS_HOST/oidc/.well-known/oauth-authorization-server" \
  | python -c 'import json,sys; d=json.load(sys.stdin); print({k:d.get(k) for k in ("issuer","token_endpoint","token_endpoint_auth_methods_supported")})'
python scripts/mcp_smoke.py
```

The script is `challenge/scripts/mcp_smoke.py`. It uses the Python `mcp` streamable-HTTP client,
the same transport Strands builds, because MCP servers expect the initialize handshake and a bare
`tools/list` POST may be rejected.

- **Grants experiment.** The call runs with the four grants from step 4. If it returns 3, the
  function reads tables with its owner's rights and the agent never needs `SELECT` on silver;
  the four-grant query is the stronger governance artifact and `SELECT` waits for the Genie spec.
  If it fails on table access, add `"SELECT"` to `agent_silver` in `main.tf`, apply, rerun, and
  write down why.
- **Done when.** The discovery request returns 200 with an issuer and token endpoint; the
  per-function URL lists one tool and the call returns 3; the schema-level result, pass or fail,
  is recorded. On a serverless compute permission error, check that Default Interactive Compute
  still includes All Users ([serverless access control](https://docs.databricks.com/aws/en/compute/serverless/access-control)).

## Step 10: next morning, record what the smoke call billed to

Billing rows arrive within about 12 hours and need account-admin or metastore-admin rights
([billing table](https://docs.databricks.com/aws/en/admin/system-tables/billing)).

```sql
SELECT sku_name, billing_origin_product, usage_quantity, usage_start_time
FROM system.billing.usage
WHERE usage_start_time >= current_date() - 1
ORDER BY usage_start_time DESC;
```

- **Done when.** The SKU behind the function call is in `01-results.md`. If the table is not
  readable, the account console Usage page is the fallback.

## Step 11: egress check from a serverless notebook

Trial accounts on personal emails get "limited external network access"; a custom domain may or
may not count as business.

```python
import requests
print(requests.get("https://data.opm.gov/api/v1/files/separations?current=true&year=2026", timeout=30).status_code)
print(requests.get("https://data.usajobs.gov/api/historicjoa?HiringDepartmentCodes=HS&StartPositionOpenDate=2026-10-01&EndPositionOpenDate=2026-10-01",
                   headers={"User-Agent": "workforce-agent/0.1"}, timeout=60).status_code)
```

- **Done when.** Both print 200. If blocked, add the payment method and retest; if still blocked,
  the ingest spec downloads locally and uploads to a Unity Catalog volume.

## Results file

`challenge/specs/01-results.md`, committed, redacted per the Rule: region, trial end date, serverless notebook
check, warehouse settings, the step 4 grants query (four or five rows, with the reason),
preview on, OAuth discovery facts, per-function vs schema-level MCP URL, billing SKU, egress
result, and anything that did not match this spec.

## Teardown

The week after the interview, per the [cost estimate checklist](../../wiki/analyses/build-cost-estimate.md).
First `terraform destroy` in `challenge/infra` (warehouse, catalog with its data, service
principal, secret scope), then delete the local state files. If a payment method was added,
remove it after the compute is gone so the account cannot bill.

## Not verified before writing

- Whether the trial warehouse starts without a payment method.
- Whether serverless notebooks and jobs work on an express trial (step 1 checks); the trial doc
  says they do, capped at 50 DBU/hr.
- Whether a Unity Catalog SQL function reads tables with owner or invoker rights (step 9 checks).
- Whether the schema-level MCP functions URL exists (step 9 checks).
- Whether an express trial has a Starter Warehouse at all (step 3 has the fallback), and whether
  a serverless warehouse accepts `auto_stop_mins = 5` (apply rejects it if not).
- Whether the service principal needs workspace access as well as SQL access to call the MCP
  endpoints. A 403 in step 9 points here.
