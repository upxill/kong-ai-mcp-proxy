# Connecting clients

All clients use **Streamable HTTP** to the route URL, e.g. `https://<proxy-url>/petstore`.

## curl (raw protocol)

```bash
URL=https://<proxy-url>/petstore
H=(-H 'Content-Type: application/json' -H 'Accept: application/json, text/event-stream')
# add -H 'apikey: ...' to H if the route has key-auth

# 1. initialize -> read the mcp-session-id response header
curl -i -X POST $URL "${H[@]}" \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"curl","version":"1.0"}}}'
SID=<mcp-session-id>

# 2. initialized notification
curl -s -X POST $URL "${H[@]}" -H "mcp-session-id: $SID" \
  -d '{"jsonrpc":"2.0","method":"notifications/initialized"}'

# 3. list tools
curl -s -X POST $URL "${H[@]}" -H "mcp-session-id: $SID" \
  -d '{"jsonrpc":"2.0","id":2,"method":"tools/list"}'

# 4. call a tool
curl -s -X POST $URL "${H[@]}" -H "mcp-session-id: $SID" \
  -d '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"find-pets-by-status","arguments":{"query_status":"available"}}}'
```

Or run everything at once: `./scripts/mcp-smoke-test.sh $URL`.

Responses arrive as server-sent events:

```
event: message
data: {"jsonrpc":"2.0","id":2,"result":{"tools":[ ... ]}}
```

## MCP Inspector

```bash
npx @modelcontextprotocol/inspector
```

Transport **Streamable HTTP** → URL → (Authentication → header `apikey` if needed) → **Connect** → **Tools → List Tools** → run a tool.

## Claude Code

```bash
# no auth
claude mcp add --transport http petstore https://<proxy-url>/petstore

# with key-auth
claude mcp add --transport http petstore https://<proxy-url>/petstore \
  --header "apikey: ${PETSTORE_MCP_KEY}"

claude mcp list            # check it connects
```

| `--scope` | Stored | Available to |
| --- | --- | --- |
| `local` (default) | your user config, this project | You, this project |
| `project` | `.mcp.json` in the repo | Everyone who clones the repo |
| `user` | your user config | You, every project |

Project config ([.mcp.json.example](../.mcp.json.example)):

```json
{
  "mcpServers": {
    "petstore": {
      "type": "http",
      "url": "https://<proxy-url>/petstore",
      "headers": { "apikey": "${PETSTORE_MCP_KEY}" }
    }
  }
}
```

Claude Code expands `${VAR}` from your environment, so keys stay out of git. In a session, `/mcp` shows status and tools. Ask in plain language: "What pets are available?"

For OAuth-protected endpoints (AI MCP OAuth2), add the server without a header; Claude Code discovers the authorization server and opens the browser login. Use `/mcp` to authenticate.

## Cursor

`~/.cursor/mcp.json` (global) or `.cursor/mcp.json` (project):

```json
{
  "mcpServers": {
    "petstore": {
      "url": "https://<proxy-url>/petstore",
      "headers": { "apikey": "<key>" }
    }
  }
}
```

## Claude Desktop

Use **Settings → Connectors → Add custom connector** with the URL (remote MCP servers), or a local bridge such as `mcp-remote`:

```json
{
  "mcpServers": {
    "petstore": {
      "command": "npx",
      "args": ["-y", "mcp-remote", "https://<proxy-url>/petstore", "--header", "apikey:${PETSTORE_MCP_KEY}"],
      "env": { "PETSTORE_MCP_KEY": "<key>" }
    }
  }
}
```

## Programmatic (Python MCP SDK)

```python
import asyncio
from mcp import ClientSession
from mcp.client.streamable_http import streamablehttp_client

URL = "https://<proxy-url>/petstore"

async def main():
    async with streamablehttp_client(URL, headers={"apikey": "<key>"}) as (read, write, _):
        async with ClientSession(read, write) as s:
            await s.initialize()
            tools = await s.list_tools()
            print([t.name for t in tools.tools])
            r = await s.call_tool("find-pets-by-status", {"query_status": "available"})
            print(r.content[0].text[:500])

asyncio.run(main())
```

`pip install mcp`.
