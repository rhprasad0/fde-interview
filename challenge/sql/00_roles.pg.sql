-- Spec 06: schemas and the agent's read-only role. Run once as the master user, rerunnable:
--   psql -v agent_password="$AGENT_PGPASSWORD" -f challenge/sql/00_roles.pg.sql
-- The master user (PG* in challenge/.env) owns every object; the agent role sees schema semantic only.
-- SELECT on the views and EXECUTE on the functions are granted at the end of 03_semantic.pg.sql,
-- after the objects exist.

CREATE SCHEMA IF NOT EXISTS silver;
CREATE SCHEMA IF NOT EXISTS synthetic;
CREATE SCHEMA IF NOT EXISTS semantic;

-- psql does not interpolate :'var' inside a DO body, so the guard runs through \gexec instead.
SELECT 'CREATE ROLE agent LOGIN' WHERE NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'agent') \gexec
ALTER ROLE agent PASSWORD :'agent_password';
ALTER ROLE agent SET statement_timeout = '60s';  -- whole-DHS calls (attrition_ranking) scan a full month: ~20 s alone on the micro
ALTER ROLE agent SET default_transaction_read_only = on;
ALTER ROLE agent SET search_path = semantic;
ALTER ROLE agent SET effective_io_concurrency = 32;  -- prefetch on bitmap heap scans; the micro's disk is the bottleneck
ALTER ROLE workforce SET effective_io_concurrency = 32;
GRANT USAGE ON SCHEMA semantic TO agent;
