#!/usr/bin/env bash
# MCP smoke test: initialize -> notifications/initialized -> tools/list -> tools/call
#
# Usage:
#   ./scripts/mcp-smoke-test.sh <mcp-url> [tool-name] [json-arguments]
#
# Examples:
#   ./scripts/mcp-smoke-test.sh https://<proxy>/petstore
#   ./scripts/mcp-smoke-test.sh https://<proxy>/petstore find-pets-by-status '{"query_status":"available"}'
#   APIKEY=xxxx ./scripts/mcp-smoke-test.sh https://<proxy>/petstore-secure
#
# Env: APIKEY (sent as "apikey" header), BEARER (sent as Authorization: Bearer ...)
set -euo pipefail

URL="${1:?usage: $0 <mcp-url> [tool-name] [json-arguments]}"
TOOL="${2:-}"
ARGS="${3:-{\}}"

HDRS=(-H 'Content-Type: application/json' -H 'Accept: application/json, text/event-stream')
[[ -n "${APIKEY:-}" ]] && HDRS+=(-H "apikey: ${APIKEY}")
[[ -n "${BEARER:-}" ]] && HDRS+=(-H "Authorization: Bearer ${BEARER}")

# SSE "data:" lines -> JSON
sse_json() { sed -n 's/^data: //p'; }
pretty() { if command -v jq >/dev/null; then jq "$@"; else cat; fi; }

echo "== 1. initialize"
HEADERS_FILE="$(mktemp)"
BODY=$(curl -sS -D "$HEADERS_FILE" -X POST "$URL" "${HDRS[@]}" \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"mcp-smoke-test","version":"1.0"}}}')
STATUS=$(head -1 "$HEADERS_FILE" | awk '{print $2}')
SID=$(grep -i '^mcp-session-id:' "$HEADERS_FILE" | awk '{print $2}' | tr -d '\r')
rm -f "$HEADERS_FILE"
echo "HTTP $STATUS  session=$SID"
if [[ "$STATUS" != "200" || -z "$SID" ]]; then
  echo "$BODY"; echo "FAIL: initialize did not return 200 with an mcp-session-id"; exit 1
fi
echo "$BODY" | sse_json | pretty -c '.result.serverInfo'

SH=("${HDRS[@]}" -H "mcp-session-id: $SID")

echo "== 2. notifications/initialized"
curl -sS -o /dev/null -w "HTTP %{http_code}\n" -X POST "$URL" "${SH[@]}" \
  -d '{"jsonrpc":"2.0","method":"notifications/initialized"}'

echo "== 3. tools/list"
LIST=$(curl -sS -X POST "$URL" "${SH[@]}" -d '{"jsonrpc":"2.0","id":2,"method":"tools/list"}' | sse_json)
if command -v jq >/dev/null; then
  echo "$LIST" | jq -r '.result.tools[] | "  \(.name)  args=\(.inputSchema.properties | keys | join(","))"'
else
  echo "$LIST"
fi

if [[ -z "$TOOL" ]]; then
  TOOL=$(echo "$LIST" | jq -r '[.result.tools[] | select((.inputSchema.required // []) | length == 0)][0].name // empty' 2>/dev/null || true)
  [[ -z "$TOOL" ]] && { echo "Pass a tool name to test tools/call."; exit 0; }
  ARGS='{}'
fi

echo "== 4. tools/call $TOOL $ARGS"
CALL=$(curl -sS -X POST "$URL" "${SH[@]}" \
  -d "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"tools/call\",\"params\":{\"name\":\"$TOOL\",\"arguments\":$ARGS}}" | sse_json)
if command -v jq >/dev/null; then
  ERR=$(echo "$CALL" | jq -r '.result.isError // false')
  echo "$CALL" | jq -r '.result.content[0].text // .error' | head -c 1500; echo
  [[ "$ERR" == "true" ]] && { echo "FAIL: tool returned isError=true"; exit 1; }
else
  echo "$CALL"
fi
echo "OK"
