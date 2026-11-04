-- The OPM watcher's manifest: one row per current OPM FWD file landed in S3 (challenge/infra/pipeline.tf). Run as the
-- master user, rerunnable:
--   psql -v pipeline_password="$PIPELINE_PGPASSWORD" -f challenge/sql/05_pipeline.pg.sql
-- The loader Lambda writes as role pipeline, which can insert here and nothing else. The agent role gets no grant on
-- schema ops: what landed is not what the agent reads until load_postgres.py --ship is rerun by hand.

CREATE SCHEMA IF NOT EXISTS ops;

CREATE TABLE IF NOT EXISTS ops.opm_files (
  filename         text PRIMARY KEY,           -- e.g. separations_202609_1; a new version is a new row
  dataset          text NOT NULL,
  data_month       date NOT NULL,
  version          int NOT NULL,
  opm_published_at timestamptz NOT NULL,       -- OPM's publishDate
  bytes            bigint NOT NULL,
  s3_key           text NOT NULL,
  landed_at        timestamptz NOT NULL DEFAULT now()
);

SELECT 'CREATE ROLE pipeline LOGIN' WHERE NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'pipeline') \gexec
ALTER ROLE pipeline PASSWORD :'pipeline_password';
ALTER ROLE pipeline SET statement_timeout = '5s';
GRANT USAGE ON SCHEMA ops TO pipeline;
GRANT INSERT ON ops.opm_files TO pipeline;  -- ON CONFLICT DO NOTHING needs no more than this
