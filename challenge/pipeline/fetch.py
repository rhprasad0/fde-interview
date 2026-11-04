"""The OPM watcher, step 1 (challenge/infra/pipeline.tf): land each new current OPM FWD file in S3, then hand its
metadata to load.py, which records it in ops.opm_files. Runs daily outside the VPC because it needs the internet and
the VPC has no NAT; the loader runs inside it because RDS admits only security groups and one laptop address.

Lands files only. The agent's tables are rebuilt by hand (scripts/load_postgres.py --ship) from a pinned month window,
so a new month never changes the numbers the eval truth was computed against.
"""

import datetime
import json
import os
import urllib.request

import boto3
from botocore.exceptions import ClientError

OPM = "https://data.opm.gov/api/v1/files"
DATASETS = ("employment", "separations", "accessions")
BUCKET, LOADER, SINCE = os.environ["BUCKET"], os.environ["LOADER"], os.environ["SINCE"]  # SINCE is YYYYMM
s3, lam = boto3.client("s3"), boto3.client("lambda")


def get(url):
    return urllib.request.urlopen(urllib.request.Request(url, headers={"User-Agent": "workforce-pipeline/0.1"}), timeout=120)


def landed(key):
    try:
        s3.head_object(Bucket=BUCKET, Key=key)
        return True
    except ClientError as e:
        if e.response["Error"]["Code"] != "404":
            raise
        return False


def handler(event, context):
    new = []
    for dataset in DATASETS:
        for year in range(int(SINCE[:4]), datetime.date.today().year + 1):
            for f in json.load(get(f"{OPM}/{dataset}?current=true&year={year}")):
                key = f"opm/{dataset}/{f['filename']}.parquet"
                if f["year"] + f["month"] < SINCE or landed(key):
                    continue
                with get(f"{OPM}/{dataset}/{f['year']}/{f['month']}/{f['version']}/download") as r:
                    s3.upload_fileobj(r, BUCKET, key)
                row = {"filename": f["filename"], "dataset": dataset, "data_month": f"{f['year']}-{f['month']}-01",
                       "version": f["version"], "opm_published_at": f["publishDate"],
                       "bytes": s3.head_object(Bucket=BUCKET, Key=key)["ContentLength"], "s3_key": key}
                resp = lam.invoke(FunctionName=LOADER, Payload=json.dumps(row))
                if "FunctionError" in resp:
                    s3.delete_object(Bucket=BUCKET, Key=key)  # unrecorded file: drop it so tomorrow's run retries
                    raise RuntimeError(f"{key}: {resp['Payload'].read().decode()}")
                print("landed", key, row["bytes"], "bytes")
                new.append(key)
    print(len(new), "new files")
    return new
