"""Spec 01 step 9: authenticate as the service principal and call one Unity Catalog function over MCP.

Reads DATABRICKS_HOST, DATABRICKS_CLIENT_ID, DATABRICKS_CLIENT_SECRET from the environment.
Prints redacted output; never prints the token or the secret.
"""

import asyncio
import os

import httpx
from mcp import ClientSession
from mcp.client.streamable_http import streamablehttp_client

HOST = os.environ["DATABRICKS_HOST"].rstrip("/")
FN_URL = f"{HOST}/api/2.0/mcp/functions/workforce/semantic/headcount_for"
SCHEMA_URL = f"{HOST}/api/2.0/mcp/functions/workforce/semantic"
# all-apis is capped by the secret's own scopes (unity-catalog, genie). If the token endpoint
# rejects it, change to "unity-catalog" and record which string worked.
SCOPE = "all-apis"


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
    async with streamablehttp_client(url, headers={"Authorization": f"Bearer {tok}"}) as (r, w, _):
        async with ClientSession(r, w) as s:
            await s.initialize()
            tools = await s.list_tools()
            names = [t.name for t in tools.tools]
            print(url.replace(HOST, "<workspace>"), "->", names)
            fn = next(n for n in names if n.endswith("headcount_for"))
            res = await s.call_tool(fn, {"agency": "HS"})
            texts = [c.text for c in res.content if hasattr(c, "text")]
            print("   call ->", texts)
            assert any("3" in t for t in texts), "expected 3"


async def main() -> None:
    tok = token()
    await probe(FN_URL, tok)
    try:
        await probe(SCHEMA_URL, tok)
        print("schema-level URL works: one Gateway target per schema")
    except Exception as e:  # noqa: BLE001
        print("schema-level URL not supported, one Gateway target per function:", type(e).__name__)


asyncio.run(main())
