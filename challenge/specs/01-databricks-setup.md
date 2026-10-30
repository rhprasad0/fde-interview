# Spec 01: Databricks on AWS, set up and ready for AgentCore

**Goal.** A Databricks workspace in `us-east-1`, billed through Ryan's AWS account, with Unity
Catalog laid out, a read-only service principal, the Managed MCP Servers preview on, and one
proof: an external MCP client authenticates as the service principal and calls one Unity Catalog
function, and records the three OAuth facts the AgentCore Gateway spec needs.

**Out of scope.** Lakeflow ingest; the Genie space (needs data); any AgentCore resource; AWS
Budgets for AgentCore; MLflow; the eval harness; the dashboard. Each gets its own spec.

**Implements.** Platform, Region, MCP path, Domain model (read-only), Observability
(`DECISIONS.md`, 2026-10-30). Costs in [the cost estimate](../../wiki/analyses/build-cost-estimate.md).

**Identities.** Ryan's admin user does every step and owns the catalog. The Lakeflow job and the
eval notebook in later specs run as that same user, so no job identity, no secret-scope ACL, and
no write grant is created here. The service principal `workforce-agent` is the only other
identity and it only reads.

**Rule.** No workspace URL, account id, warehouse id, client id, or secret in any tracked file
(`AGENTS.md`). Real values go in `challenge/.env` (gitignored); commit only `challenge/example.env`.
Before pasting any console or script output into `01-results.md`, replace the host with
`<workspace>` and the application id with `<application-id>`.

**Budget.** Under $5 of trial credit. Nothing runs unattended.

## Step 1: sign up through AWS Marketplace, confirm region and serverless

- **Why Marketplace.** It links the AWS account and bills through it after credits; express setup
  bills a card ([Marketplace signup](https://docs.databricks.com/aws/en/getting-started/cloud-setup)).
  The AWS identity needs `AWSMarketplaceFullAccess` or `AWSMarketplaceManageSubscriptions`. A
  serverless workspace deploys nothing into the AWS account. Do not create a classic workspace;
  it provisions a VPC and NAT gateway that AWS bills directly.
- **Do.** AWS Marketplace, Databricks listing, start the free trial, create the Databricks account
  with the business email, Continue to Databricks.
- **Region.** If the auto-created workspace is not in `us-east-1`: account console, Workspaces,
  Create workspace, "Use serverless compute and default storage," region `us-east-1`, use that one.
- **Done when.** Manage trial shows the credit balance; the region is `us-east-1`; a new
  serverless notebook runs `print(1)`. The notebook check settles whether serverless notebooks
  and jobs work on this trial type, which the ingest and eval specs depend on. Record the
  workspace URL in `.env`.

## Step 2: budgets

- **Do.** Account console, Usage, Budgets. Two budgets, alert at $25 and $45, email to Ryan.
- **Done when.** Both show active.

## Step 3: the SQL warehouse

- **Do.** SQL Warehouses. The workspace auto-creates a Starter Warehouse and the trial allows one
  ([SQL warehouse](https://docs.databricks.com/aws/en/compute/sql-warehouse)). Edit it: serverless,
  2X-Small, auto-stop at the minimum the UI allows, scaling 1 to 1. Create one only if none exists.
  If it refuses to start, add the payment method via Manage trial; credits survive
  ([conflict noted here](../../wiki/analyses/build-cost-estimate.md)).
- **Done when.** `SELECT 1` runs and the warehouse stops after idle. Record the warehouse id in
  `.env` for later specs.

## Step 4: catalog and schemas

```sql
CREATE CATALOG IF NOT EXISTS workforce;
USE CATALOG workforce;
CREATE SCHEMA IF NOT EXISTS bronze   COMMENT 'Raw OPM FWD and USAJOBS files, versioned as received';
CREATE SCHEMA IF NOT EXISTS silver   COMMENT 'Typed, deduplicated tables with stable keys';
CREATE SCHEMA IF NOT EXISTS semantic COMMENT 'Ontology-like layer: governed views and functions the agent may call';
CREATE SCHEMA IF NOT EXISTS eval     COMMENT 'Golden questions, per-run results, dashboard source';
```

- **Done when.** Catalog Explorer shows the four schemas with comments.

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

## Step 6: the read-only service principal

- **Create.** Settings, Identity and access, Service principals, Add. Name `workforce-agent`.
  Add it to the workspace with the Databricks SQL access entitlement (Genie consumers need it
  later, [Genie setup](https://docs.databricks.com/aws/en/genie/set-up)). The application id is
  the OAuth client id.
- **Secret.** Secrets, Generate secret. Lifetime 60 days, so it outlives an unscheduled interview.
  Scopes `unity-catalog` and `genie` only ([scopes](https://docs.databricks.com/api/workspace/scopes));
  scopes are fixed at generation ([OAuth M2M](https://docs.databricks.com/aws/en/dev-tools/auth/oauth-m2m)).
  Copy the secret once into `.env`.
- **Grants, first pass.** Four grants, no `SELECT` yet:

```sql
USE CATALOG workforce;
GRANT USE CATALOG ON CATALOG workforce TO `<application-id>`;
GRANT USE SCHEMA ON SCHEMA silver   TO `<application-id>`;
GRANT USE SCHEMA ON SCHEMA semantic TO `<application-id>`;
GRANT EXECUTE ON FUNCTION semantic.headcount_for TO `<application-id>`;
SHOW GRANTS TO `<application-id>`;
```

  Run step 9 with these four. If the call returns 3, the function runs with the owner's rights on
  the tables it reads and the agent never needs `SELECT` on silver; that four-grant `SHOW GRANTS`
  is the stronger governance artifact and `SELECT` waits for the Genie spec. If the call fails on
  table access, add `GRANT SELECT ON SCHEMA silver TO ...` and write down why.
- **Done when.** `SHOW GRANTS` lists exactly the grants above and nothing on `bronze` or `eval`.

## Step 7: enable Managed MCP Servers

- **Do.** Settings, Previews, enable Managed MCP Servers ([built-in MCPs](https://docs.databricks.com/aws/en/agents/mcp-tools/built-in-mcp-services)).
  Leave the Unity Gateway beta off; the chosen path does not use it.
- **Done when.** The preview shows On.

## Step 8: secret scope for the USAJOBS key

```bash
databricks secrets create-scope workforce
databricks secrets put-secret workforce usajobs_api_key   # paste when prompted
databricks secrets put-secret workforce usajobs_email
```

- **Done when.** `databricks secrets list-secrets workforce` shows both keys.

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

`challenge/specs/01-results.md`, committed, redacted per the Rule: region, serverless notebook
check, warehouse settings, the final `SHOW GRANTS` (four or five grants, with the reason),
preview on, OAuth discovery facts, per-function vs schema-level MCP URL, billing SKU, egress
result, and anything that did not match this spec.

## Teardown

The week after the interview, per the [cost estimate checklist](../../wiki/analyses/build-cost-estimate.md),
plus cancel the Marketplace subscription so the account does not roll to pay-as-you-go.

## Not verified before writing

- Whether the Marketplace flow lets you choose the region of the auto-created workspace.
- Whether the trial warehouse starts without a payment method.
- Whether serverless notebooks and jobs are available on a Marketplace trial (step 1 checks).
- Whether a Unity Catalog SQL function reads tables with owner or invoker rights (step 6 checks).
- Whether the schema-level MCP functions URL exists (step 9 checks).
