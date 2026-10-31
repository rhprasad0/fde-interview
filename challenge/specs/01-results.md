# Spec 01 results

Executed 2026-10-31. Redacted per the Rule: host is `<workspace>`, the service principal's
application id is `<application-id>`. Spec: [01-databricks-setup.md](01-databricks-setup.md).

## Summary

Everything the AgentCore Gateway spec needs is green: OAuth discovery, a scoped M2M token, and a
Unity Catalog function called over MCP as the read-only service principal, at both the function
and the schema URL. The billing SKU (step 10, due 2026-11-01) is open. Serverless egress to OPM
and USAJOBS is **blocked** (step 11) and stays blocked after adding a payment method, so the
source files are uploaded from a laptop to a volume (`DECISIONS.md`, Ingest). That makes step 8
unnecessary: the USAJOBS key stays in `challenge/.env`.

## By step

| Step | Result |
|---|---|
| 1 Signup | Direct express trial, no payment method; one was added later the same day (step 11). Region `us-west-2`, assigned with no choice offered. Trial ends **2026-11-14**. Serverless notebooks work both ways: interactively (attached to Serverless, Run all) and as a one-off job's notebook task. |
| 2 Budgets | One budget, whole account, thresholds at $25 and $45 with email alerts. The UI takes up to four thresholds per budget, so one budget replaced the spec's two. |
| 3 Warehouse | A "Serverless Starter Warehouse" existed (Small, auto-stop 10 minutes). |
| 4 Terraform | Imported the warehouse and changed it to 2X-Small, auto-stop 5 minutes (accepted), one cluster; it stops after idle. The catalog cannot be created by the provider on default storage (see Deviations). A second `terraform plan` reports no changes. |
| 5 Smoke | `workforce.semantic.headcount_for('HS')` returns 3. |
| 6 Secret | Generated in the UI with scopes `unity-catalog` and `genie`. |
| 7 Preview | Managed MCP Servers is on the workspace Previews page (username menu, Previews), not Settings. The three Unity Gateway betas were on by default in the account console and left alone; the workspace MCP endpoints bypass Unity Gateway. |
| 8 USAJOBS secrets | **Skipped.** Scope `workforce` exists (Terraform) but holds nothing: no workspace job calls USAJOBS while egress is blocked. |
| 9 MCP handshake | Pass. Facts below. |
| 10 Billing SKU | **Open**, due 2026-11-01. |
| 11 Egress | **Blocked.** Details below. |

## Grants (step 4 query)

```
catalog | workforce | USE_CATALOG
schema  | semantic  | EXECUTE
schema  | semantic  | USE_SCHEMA
schema  | silver    | USE_SCHEMA
```

Four rows, nothing on `bronze` or `eval`. The step 9 call returned 3 with these four, so a SQL
function reads its tables with the owner's rights and the agent needs no `SELECT` on silver.
`SELECT` waits for the Genie spec.

## OAuth and MCP facts for the AgentCore Gateway spec

- **Discovery.** `GET <workspace>/oidc/.well-known/oauth-authorization-server` returns 200. Issuer
  `<workspace>/oidc`, token endpoint `<workspace>/oidc/v1/token`, auth methods
  `client_secret_basic`, `client_secret_post`, `none`.
- **Token.** `client_credentials` with `client_secret_basic` and scope `unity-catalog genie`
  returns a bearer token valid 3600 seconds. `all-apis` is refused: 403 `access_denied`, "Scopes
  'all-apis' are not assigned to the client". The requested scope must be a subset of the
  secret's scopes.
- **MCP URL.** Both work: per function `<workspace>/api/2.0/mcp/functions/workforce/semantic/headcount_for`
  and per schema `<workspace>/api/2.0/mcp/functions/workforce/semantic`. The docs (updated
  2026-10-23) document only the per-function form. **One Gateway target per schema.**
- **Tool names** come back as `workforce__semantic__headcount_for` (`catalog__schema__function`).
  The tool result is JSON text: `{"is_truncated":false,"columns":["output"],"rows":[[3]]}`.
- **Disabled preview** answers HTTP 200 with JSON-RPC error `-32602`, "NOT_FOUND: Databricks
  managed MCP servers are not enabled". Error handling must read the JSON-RPC body, not the status.
- **Workspace access** is not needed: the service principal has SQL access only and every call
  succeeded.

## Egress from serverless (step 11)

A serverless notebook job resolved and fetched each host:

| Host | DNS | HTTPS |
|---|---|---|
| data.opm.gov | fails (`Temporary failure in name resolution`) | fails |
| data.usajobs.gov | fails | fails |
| www.google.com | fails | fails |
| pypi.org | resolves | 200 |
| github.com | resolves | 200 |
| api.anthropic.com | resolves | 404 (reachable) |

The AWS hosts the eval harness calls do resolve: `bedrock-agentcore.us-west-2.amazonaws.com`,
`sts.us-west-2.amazonaws.com`, `sts.amazonaws.com` (DNS only; no signed request sent).

An allowlist enforced at DNS: the trial's "limited external network access".
`system.access.outbound_network` records each refused lookup as `access_type = DROP`,
`destination_type = DNS`, rcode 5 (REFUSED).

- **Network policies** could allow the two federal hosts but need the Enterprise tier
  ([network policies](https://docs.databricks.com/aws/en/security/network/serverless-network-security/manage-network-policies)).
  This account is not on it.
- **A payment method** was added. Reruns right after and 15 minutes later gave the same table.
- **Cause, per a Databricks employee:** the block is tied to account verification, not the
  billing plan; the account team can lift it
  ([forum thread](https://community.databricks.com/t5/administration-architecture/serverless-egress-blocked-despite-full-access-network-policy/td-p/173281)).
  Not pursued: see `DECISIONS.md`, Ingest.

## Deviations from the spec

- **Signup and region.** Direct trial instead of Marketplace; `us-west-2` instead of `us-east-1`
  (`DECISIONS.md`, 2026-10-31).
- **Catalog.** `databricks_catalog` fails with "Metastore storage root URL does not exist. Default
  Storage is enabled in your account." Created in SQL, imported into Terraform, with
  `storage_root` and `properties` (a server-set collation) in `ignore_changes`. Spec step 4 now
  says so.
- **Landing volume.** Added to `main.tf` after step 11 for the ingest decision. Unlike the
  catalog, `databricks_volume` creates a managed volume on default storage directly; a second
  plan reports no changes.
- **Entitlement.** A separate `databricks_entitlements` resource fought the service principal
  resource's own `databricks_sql_access = false` default; the entitlement now sits on the
  service principal.
- **MCP SDK.** `mcp` 2.3 renamed `streamablehttp_client` to `streamable_http_client` and takes an
  `httpx2` client for headers; `mcp_smoke.py` is updated and the spec pins `mcp>=2.3,<3`.
- **Scope string.** `all-apis` is refused; the script requests `unity-catalog genie`.
