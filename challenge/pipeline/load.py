"""The OPM watcher, step 2 (challenge/infra/pipeline.tf): record one landed file in ops.opm_files as role pipeline,
which can insert there and nothing else (challenge/sql/05_pipeline.pg.sql). Invoked by fetch.py with the row."""

import os
import ssl

import pg8000.native

# shortcut: encrypted but unverified, the same as the app's PGSSLMODE=require; bundle the RDS CA to verify.
TLS = ssl.create_default_context()
TLS.check_hostname, TLS.verify_mode = False, ssl.CERT_NONE


def handler(row, context):
    con = pg8000.native.Connection(host=os.environ["PGHOST"], database=os.environ["PGDATABASE"],
                                   user=os.environ["PGUSER"], password=os.environ["PGPASSWORD"], ssl_context=TLS)
    try:
        con.run("INSERT INTO ops.opm_files (filename, dataset, data_month, version, opm_published_at, bytes, s3_key) "
                "VALUES (:filename, :dataset, CAST(:data_month AS date), :version, CAST(:opm_published_at AS timestamptz), "
                ":bytes, :s3_key) ON CONFLICT DO NOTHING", **row)
    finally:
        con.close()
    return row["filename"]
