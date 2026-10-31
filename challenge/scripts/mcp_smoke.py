"""Spec 01 step 9, retargeted by spec 03: authenticate as the service principal and call one
semantic-layer function over MCP (spec 01 used the smoke function headcount_for, which spec 03 drops).

Reads DATABRICKS_HOST, DATABRICKS_CLIENT_ID, DATABRICKS_CLIENT_SECRET from the environment.
Prints redacted output; never prints the token or the secret.
"""

import asyncio
import os

import httpx
import httpx2  # the transport mcp>=2 requires
from mcp import ClientSession
from mcp.client.streamable_http import streamable_http_client

HOST = os.environ["DATABRICKS_HOST"].rstrip("/")
FN_URL = f"{HOST}/api/2.0/mcp/functions/workforce/semantic/separation_rate"
SCHEMA_URL = f"{HOST}/api/2.0/mcp/functions/workforce/semantic"
# Must be a subset of the secret's scopes; "all-apis" is refused with 403 access_denied.
SCOPE = "unity-catalog genie"


def token() -> str:
    r = httpx.post(
        f"{HOST}/oidc/v1/token",
        auth=(os.environ["DATABRICKS_CLIENT_ID"], os.environ["DATABRICKS_CLIENT_SECRET"]),
        data={"grant_type": "client_credentials", "scope": SCOPE},
        timeout=30,
    )
    r.raise_for_status()
    print(f"token ok: auth=client_secret_basic scope={SCOPE}")
    return r.json()["access_token"]


async def probe(url: str, tok: str) -> None:
    async with (
        httpx2.AsyncClient(headers={"Authorization": f"Bearer {tok}"}, timeout=60) as http,
        streamable_http_client(url, http_client=http) as (r, w),
    ):
        async with ClientSession(r, w) as s:
            await s.initialize()
            tools = await s.list_tools()
            names = [t.name for t in tools.tools]
            print(url.replace(HOST, "<workspace>"), "->", names)
            fn = next(n for n in names if n.endswith("separation_rate"))
            # TSA screeners, trailing twelve months to the latest snapshot (spec 03 step 7).
            res = await s.call_tool(fn, {"as_of_month": "2026-08-01", "component": "HSBC", "series": "1802"})
            texts = [c.text for c in res.content if hasattr(c, "text")]
            print("   call ->", texts)
            assert any('"rows":[[' in t for t in texts), "expected at least one result row"


async def main() -> None:
    tok = token()
    await probe(FN_URL, tok)
    try:
        await probe(SCHEMA_URL, tok)
        print("schema-level URL works: one Gateway target per schema")
    except Exception as e:  # noqa: BLE001
        print("schema-level URL not supported, one Gateway target per function:", type(e).__name__)


asyncio.run(main())
