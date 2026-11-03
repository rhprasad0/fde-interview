# Spec 06: Databricks torn down, the semantic layer on RDS Postgres

**Goal.** The same agent, eval set and demo app, with the data layer on one small Postgres
instance that costs about $14 a month and cannot surprise the budget, and nothing left on the
laptop or in the repo that can reach the Databricks workspace. Today a smoke test; the hill climb
resumes on 2026-11-03.

## Where we got to on Databricks (specs 01 to 05, 2026-10-31 to 2026-11-02)

- **Built:** a workspace in us-west-2 on the express trial; Unity Catalog `workforce` with bronze,
  silver, synthetic and semantic schemas, a landing volume, a read-only service principal, Terraform
  for the governance objects (spec 01); twelve months of OPM employment, separations and accessions
  plus the DHS slice of USAJOBS loaded from the laptop (spec 02); synthetic location and pay for
  the 76% of DHS rows OPM redacts, a synthetic staffing plan, eight semantic views and eight table
  functions as the agent's only surface, a Genie space (spec 03); a twenty-row human-authored eval
  set with independent SQL truth (spec 04); a Strands agent on Claude Haiku 5.5 reaching the
  functions and Genie over the workspace's managed MCP endpoints, with a trace writer and the
  harness (spec 05).
- **Measured** (`challenge/eval/journal.md`): a baseline of Verified 56%, Genie 54%, Not available
  100% pooled; after four kept prompt iterations, Verified 100% (60/60), Genie 83% (100/120), Not
  available 100%, zero errors, with 17/20 and 14/20 rows passing every run of a five-run
  experiment. Two further iterations did not clear the noise bar. Genie direct, without the
  agent, answered the same eleven questions at 36%; its own grader never passed a wrong answer.
- **Cost:** the journal priced the climb at $2.68 of model calls. The Databricks side was never
  measured and came to $300 or more: every function call through the managed MCP functions server
  ran on serverless general compute at $0.75/DBU, and the climb's 1,720 runs made about 4,800
  calls, two thirds of them C11's thirty-call fan-out. Analysis:
  `wiki/analyses/databricks-spend-during-the-climb.md`.

## What carries over unchanged

The questions (`challenge/eval/questions.yaml`, `set_version` eval-v1), the experiments record
(`experiments.jsonl`, 1,720 rows), the prompt and skills (one new prompt hash: the one-off query
now takes SQL), the harness and its scorers, the demo app, the tester app, `pull_sources.py`, the
notebooks as the Databricks record, and the source files on disk under `challenge/data`.

## Teardown (run 2026-11-02 evening)

1. Genie space trashed; jobs `workforce-02-load` and `workforce-03-semantic` deleted; the
   `/Workspace/Users/<user>/workforce` notebooks deleted.
2. `terraform destroy`: catalog `workforce` (with every table), the five schemas, the warehouse,
   the `workforce-agent` service principal and its grants, the landing volume, the secret scope.
   The service principal's OAuth secret stopped minting tokens (the token endpoint answers 403); the
   principal still lists at the account level and Ryan removes it in the account console with the
   budget and the Managed MCP preview toggle.
   **Done 2026-11-03:** the principal, the budget, and the workspace itself were deleted through
   the account-level CLI after a sweep found them still present (the hand-off step had not been
   run). The account lists no workspaces, principals, or budgets; the AWS account held nothing
   Databricks had created (serverless workspace, no customer-cloud configs). Both OAuth profiles
   used for the sweep were removed from the laptop afterwards.
3. Laptop: the `[workforce]` profile removed from `~/.databrickscfg`; the seven `DATABRICKS_*`
   keys removed from `challenge/.env`; the Terraform state files deleted; the merged
   `demo-app` worktree removed.
4. Repo: `genie_bench.py`, `mcp_smoke.py` and the Genie space definition deleted; the guard in
   `AGENTS.md`.

## The Postgres layer

- **Infra:** `challenge/infra/main.tf`: db.t4g.micro, Postgres 17, 20 GB gp3, public behind a
  security group that admits one laptop /32, master and agent passwords from `random_password`,
  `terraform output -raw pg_env >> challenge/.env`.
- **Build:** `scripts/load_postgres.py` runs `sql/02_load.duckdb.sql` and
  `sql/03_synthetic.duckdb.sql` in DuckDB on the laptop (bronze as views over the parquet and
  JSON, filtered to DHS before anything leaves the machine; silver; the imputation pools and draw;
  the masking test; the staffing plan), asserts 25 acceptance numbers from specs 02 and 03, and
  with `--ship` attaches Postgres and replaces eight tables: `silver.job_postings`,
  `silver.agency_subelements`, `silver.occupational_series`, `synthetic.employment`,
  `synthetic.separations`, `synthetic.accessions`, `synthetic.staffing_plan`,
  `synthetic.imputation_quality`. Bronze never ships.
- **Semantic layer:** `sql/00_roles.pg.sql` (schemas, the `agent` role: `statement_timeout`
  60 s, `default_transaction_read_only`, `search_path = semantic`); `sql/03_semantic.pg.sql`
  (the eight views with every column comment, the eight functions with the same signatures and
  return columns as the Spark ones, text parameters cast inside, numeric casts on every rate,
  grants); `sql/checks.pg.sql` (the draw-independent acceptance numbers as assertions, the
  draw-dependent ones printed, a determinism hash).
- **The draw:** `md5(to_json(row))` and `md5_number_lower` replace `xxhash64` and `pmod`. Same
  design, different bits: imputed rows differ from Databricks; the counts (171,296
  location-imputed, 162,812 pay-imputed) reproduce. Deterministic across rebuilds (DuckDB pinned
  at 2.0.0; `state_centroids` rounded to six decimals so parallel averaging cannot move a bit).

## The agent

`prototype/agent.py`: one psycopg helper; the eight calculations built from a dict of the Spark
comments as fixed-SQL tools (`SELECT * FROM semantic.<fn>(...)`, every argument a string or null);
`one_off_query(sql)` runs one SELECT as the `agent` role, wrapped with a 500-row cap, and returns
the SQL with a hash as its statement id, so the trace fields and every scorer keep their meaning.
Tools run sequentially, one connection per live agent. The trace label `genie` stays as the name of
the exploratory tool so the history and dashboards compare. The harness fails a Verified row when
that tool ran (it used to fail on a tool with "sql" in its name). Decision entries: `DECISIONS.md`
2026-11-02, platform and exploratory tool.

## Smoke (2026-11-02 night)

1. `psql -f 00_roles.pg.sql`; `load_postgres.py --ship` (13 minutes, upload-bound; the
   2.7M-row table is 2.7 GB on Postgres); `psql -f 03_semantic.pg.sql` (clean on the first run);
   `psql -f checks.pg.sql`: every assertion passed; the determinism hash is `2f120c0c…`.
2. Role fence as `agent`: `synthetic` and `silver` denied, `CREATE TABLE` refused as read-only,
   `plan_variance('FY2026Q1','HSBD','1895')` returns (594, 475, -119, -0.2003), bare view names
   resolve through `search_path`.
3. `eval_harness.py --stub` and `pytest challenge/app/test_app.py` pass without a database.
4. `eval_harness.py truth --check`: only C09 and C10 differ (the imputed rows); re-pinned with
   `truth`. `refresh.py` rewrote `cell.json`; only the imputed state breakdown changed.
5. Live, one run of all twenty questions, twice. The first (`20261103T025340Z`) had four
   `statement_timeout` errors: DuckDB shipped rows unsorted, so one cell's rows spanned 23k random
   reads on the micro's disk. Fixed with indexes on (month, component, series), `CLUSTER` on the
   cell index, `effective_io_concurrency = 32`, the loader shipping sorted, and the agent timeout at
   60 s for whole-DHS calls. The second (`20261103T030901Z`): Verified 6/6, exploratory 10/12, Not
   available 2/2, zero errors, median latency 10 s (Genie era: 44 s). The two misses, C13 and C18,
   are model judgement rows the climb already knew. Journal: "Postgres era, iteration 0".
6. Guard: `grep -rniE 'dbc-|DATABRICKS_|databricks\.com|/api/2\.0/' --exclude-dir={.venv,.git,raw,specs} challenge`
   prints nothing; the service principal's secret answers 403.

**Open.** Narrow `synthetic.employment` to the view's 25 columns on the next ship (the table is
2.7 GB for 2.7M rows; a third of that would make whole-DHS scans fast enough to drop the timeout
back to 30 s). Ryan: remove the ghost service principal, the budget, and the MCP preview in the
Databricks account console; re-apply Terraform when the laptop IP changes.
