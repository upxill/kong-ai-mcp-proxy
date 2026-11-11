# Sessions and observability

## Sessions

`initialize` returns an `mcp-session-id`; clients send it on every later call. In `conversion-listener` and `listener` modes Kong owns the session (`config.server.session`). In `passthrough-listener` the upstream MCP server owns it.

| Strategy | Config | Use when |
| --- | --- | --- |
| Default (managed) | nothing | Single node or testing |
| `client` | `strategy: client` + `client.secrets` | Several data plane nodes, no Redis: the session is encrypted into the session id, so any node can read it |
| `redis` | `strategy: redis` + `redis.*` | Several nodes with shared state |

```yaml
config:
  server:
    session:
      managed: true
      session_ttl: 3600
      strategy: client
      client:
        secrets:
          - ${{ env "DECK_MCP_SESSION_SECRET" }}       # first one encrypts
          - ${{ env "DECK_MCP_SESSION_SECRET_OLD" }}   # older ones still decrypt (rotation)
```

```yaml
config:
  server:
    session:
      strategy: redis
      redis:
        host: redis.internal
        port: 6379
        password: ${{ env "DECK_REDIS_PASSWORD" }}
        ssl: true
```

Kong does not share sessions across instances unless you use one of these strategies. Serverless gateways may run several nodes; use `client` if you see "session not found" errors.

## Logging

```yaml
config:
  logging:
    log_statistics: true    # MCP metrics in log output
    log_payloads: false     # full request/response bodies; sensitive
    log_audits: true        # ACL allow/deny decisions
```

These add MCP fields to any Kong log plugin (HTTP Log, File Log, TCP Log, OpenTelemetry). Logged data includes the session id, JSON-RPC method, tool name, latency and errors.

```yaml
# send logs somewhere
plugins:
  - name: http-log
    route: petstore-mcp
    config:
      http_endpoint: https://logs.example.com/kong
```

## Metrics and analytics

| Where | What you get |
| --- | --- |
| Konnect → API Gateway → control plane → **Analytics** | Requests, errors, latency per route (MCP route included) |
| Konnect Explorer / Dashboards | MCP traffic when `log_statistics` is on |
| Prometheus plugin | MCP latency, response size and error counters |
| OpenTelemetry plugin | Traces and logs with MCP attributes |

References: [MCP traffic metrics](https://developer.konghq.com/ai-gateway/monitor-ai-llm-metrics/#mcp-traffic-metrics), [AI MCP audit logs](https://developer.konghq.com/ai-gateway/ai-audit-log-reference/#ai-mcp-logs).

## Limits

| Not supported | Workaround |
| --- | --- |
| Tool change notifications (`listChanged` is `false`) | Clients re-run `tools/list` after config changes |
| Multipart and XML request bodies | Front the API with JSON |
| WebSocket and gRPC upstreams | REST only |
| AI guardrail plugins on MCP traffic | Validate in the upstream API |
| Consumer / Consumer Group scoping of the plugin | Use ACLs inside the plugin |
| Sessions shared across nodes by default | `client` or `redis` session strategy |
