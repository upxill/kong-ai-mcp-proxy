# Troubleshooting

| Symptom | Cause | Fix |
| --- | --- | --- |
| `tools/call` result: `HTTP call failed with status 404: no Route matched with those values` | Tool `path` has a leading `/` that doesn't match any route (verified) | Use relative paths (`pet/findByStatus`) and put the base path in the Service URL. See [how-it-works.md](how-it-works.md#how-a-tool-path-becomes-a-url) |
| `initialize` returns `404 no Route matched` | Wrong proxy URL, wrong org, or config not synced | Check the control plane's Proxy URL; run `deck gateway diff` |
| `deck diff` says 0 changes but the UI shows nothing | Token and UI are in different Konnect orgs | Switch org in the UI (check the org **ID**), or make a token in the right org |
| `tools/call` returns upstream 404 | Base path doubled or missing | Compare: route path + relative tool path → strip_path → Service URL path. Test the REST URL with curl |
| `tools/call` rejected: invalid arguments | Wrong argument names | Use the names from `tools/list` → `inputSchema` (`query_status`, `path_petId`, `body`) |
| `tools/list` empty in `listener` mode | Tag mismatch | `conversion-only` plugin `tags` must contain the listener's `config.server.tag` |
| Conversion silently does nothing | Plugin scoped to a Service with no route | Scope the plugin to a route |
| `401` on `initialize` | Auth plugin on the route, no credential sent | Send `apikey` header / OAuth token |
| `401` on tool calls only | Auth on the route, but client headers not forwarded | Keep `server.forward_client_headers: true` |
| `403` on a tool | ACL deny, or allow list without a match | Check `default_acl` / tool `acl`; enable `include_consumer_groups` for group names; enable `log_audits` |
| `session not found` / `invalid session` | Session lost between data plane nodes or expired | Use `session.strategy: client` (or `redis`); re-run `initialize` |
| `413` / body rejected | Body over `max_request_body_size` | Raise it (default 1 MiB; `0` = unlimited) |
| Tool call times out | Upstream slower than `server.timeout` (default 10 s) | Raise `config.server.timeout` |
| OAuth2 plugin rejects internal tool calls | 3.13+ treats all traffic on its route as MCP | Use `listener` on the OAuth route and `conversion-only` on separate routes |
| Plugin rejected on sync | Not Enterprise, or Kong < 3.12 | Check license and data plane version |
| Claude Code shows the server as failed | Endpoint not reachable or auth missing | Run `./scripts/mcp-smoke-test.sh <url>`; fix Kong first |

## Debug checklist

1. `./scripts/mcp-smoke-test.sh <url>`: which step fails?
2. Call the REST API directly with curl, bypassing MCP.
3. Call the gateway route directly: `curl https://<proxy>/petstore/pet/findByStatus?status=available`. If this fails, tool calls will too.
4. Turn on `logging.log_payloads` temporarily and check your log plugin output.
5. Konnect → control plane → **Analytics** → filter by route.
