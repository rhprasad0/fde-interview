-- The review panel's decisions: what a human did with each drafted recommendation. Run as the master user, rerunnable:
--   psql -v reviewer_password="$REVIEWER_PGPASSWORD" -f challenge/sql/04_decisions.pg.sql
-- The app writes as role reviewer, which can insert here and nothing else. The agent role gets no grant on schema app,
-- so the agent stays read-only and a decision is always a human's click (DECISIONS.md, Decision capture).

CREATE SCHEMA IF NOT EXISTS app;

CREATE TABLE IF NOT EXISTS app.decisions (
  id         bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  at         timestamptz NOT NULL DEFAULT now(),
  rec        text NOT NULL,                 -- the card's stable id, e.g. committee-agenda
  verdict    text NOT NULL CHECK (verdict IN ('accept', 'edit', 'dismiss')),
  text       text NOT NULL,                 -- the recommendation as the human left it (edited text on edit)
  component  text NOT NULL,
  occupation text NOT NULL,
  period     text NOT NULL,
  session_id text NOT NULL
);

SELECT 'CREATE ROLE reviewer LOGIN' WHERE NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'reviewer') \gexec
ALTER ROLE reviewer PASSWORD :'reviewer_password';
ALTER ROLE reviewer SET statement_timeout = '5s';
ALTER ROLE reviewer SET search_path = app;
GRANT USAGE ON SCHEMA app TO reviewer;
GRANT INSERT ON app.decisions TO reviewer;
GRANT SELECT (id, at) ON app.decisions TO reviewer;  -- INSERT ... RETURNING id, at needs these two and only these
