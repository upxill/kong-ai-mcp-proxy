# Configuration reference: `ai-mcp-proxy`

Taken from the plugin schema served by a Konnect control plane running Kong Gateway **3.16.0.1 Enterprise** (`GET /v2/control-planes/{id}/core-entities/schemas/plugins/ai-mcp-proxy`). **R** = required.

## Plugin entity

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `route` / `service` | foreign | — | Where the plugin runs. Conversion modes need a route |
| `consumer`, `consumer_group` | foreign | — | Present in the schema but **not supported** for this plugin |
| `protocols` | set **R** | `[grpc, grpcs, http, https]` | Protocols it applies to |
| `tags` | array | — | Plugin-level tags. `conversion-only` plugins use them so a `listener` can find their tools |

## `config` (top level)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `mode` | string **R** | — | `passthrough-listener`, `conversion-listener`, `conversion-only`, `listener` |
| `tools` | array | — | Tool definitions ([below](#configtools)) |
| `server` | record | — | MCP server settings ([below](#configserver)) |
| `logging` | record **R** | — | Logging switches ([below](#configlogging)) |
| `max_request_body_size` | integer | `1048576` | Max MCP request body in bytes. `0` = unlimited (Nginx `client_max_body_size` still applies) |
| `default_acl` | array | — | Default ACL rules by scope ([security.md](security.md)) |
| `default_acl[].scope` | string | `tools` | Scope the rule applies to |
| `default_acl[].allow` | string array | — | Subjects allowed |
| `default_acl[].deny` | string array | — | Subjects denied; deny beats allow |
| `include_consumer_groups` | boolean | `false` | Allow consumer group names in ACLs. Listener modes only |
| `consumer_identifier` | string | `username` | What consumer ACL entries refer to: `consumer_id`, `username`, `custom_id`. Listener modes only |
| `acl_attribute_type` | string | `consumer` | Evaluate ACLs against the `consumer` or an `oauth_access_token` claim. Listener modes only |
| `access_token_claim_field` | string (min 1) | — | Claim used as the ACL subject when `acl_attribute_type: oauth_access_token`. jq path for nested claims, e.g. `.user.email` |

## `config.tools[]`

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `name` | string | slug of `annotations.title` | Tool name. In `passthrough-listener`, matches remote tools for ACLs |
| `description` | string **R** | — | Tool description shown to the AI |
| `method` | string | from route | `GET`, `PUT`, `PATCH`, `POST`, `DELETE` |
| `path` | string | from route | REST path. No leading `/` = relative to the route path |
| `host` | string | from route | Required when the route host is a wildcard |
| `scheme` | string | from route | `http` or `https` |
| `headers` | map | from route | Fixed headers for the call |
| `query` | map | — | Fixed query arguments for the call |
| `parameters` | JSON | — | OpenAPI parameters array |
| `request_body` | JSON | — | OpenAPI requestBody object |
| `responses` | JSON | — | OpenAPI responses object; maps to `structuredOutput`. One success response only |
| `annotations.title` | string | — | Human-readable title |
| `annotations.read_only_hint` | boolean | — | Does not modify anything |
| `annotations.destructive_hint` | boolean | — | May destroy or overwrite data |
| `annotations.idempotent_hint` | boolean | — | Safe to repeat |
| `annotations.open_world_hint` | boolean | — | Interacts with external entities |
| `acl.allow` | string array | — | Subjects allowed to use this tool. **Replaces** `default_acl` for this tool |
| `acl.deny` | string array | — | Subjects denied; deny beats allow |

## `config.server`

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `tag` | string | — | `listener` mode: collect tools from `conversion-only` plugins with this tag. Exactly one tag |
| `timeout` | number (ms) | `10000` | Timeout for each tool call |
| `forward_client_headers` | boolean | `true` | Forward the MCP client's request headers to tool calls |
| `session` | record | — | Managed sessions (listener and conversion-listener only) |
| `session.managed` | boolean **R** | `true` | Kong keeps MCP sessions |
| `session.session_ttl` | number (s) | `86400` | Session lifetime |
| `session.strategy` | string | — | `client` (encrypted into the session id) or `redis` |
| `session.client.secrets` | string array (min 1) | — | Encryption secrets for `client` strategy; first encrypts, all decrypt (rotation) |
| `session.redis.*` | record | — | Redis connection for the `redis` strategy (below) |

### `config.server.session.redis`

| Field | Default | Meaning |
| --- | --- | --- |
| `host` / `port` | `127.0.0.1` / `6379` | Redis address |
| `database` | `0` | Database number |
| `username` / `password` | — | Redis ACL auth (username needs Redis 6+) |
| `ssl` / `ssl_verify` / `server_name` | `false` / `false` / — | TLS |
| `connect_timeout` / `send_timeout` / `read_timeout` | `2000` ms each | Timeouts |
| `keepalive_pool_size` / `keepalive_backlog` | `256` / — | Connection pool |
| `sentinel_master` / `sentinel_role` / `sentinel_nodes[]` / `sentinel_username` / `sentinel_password` | — | Redis Sentinel |
| `cluster_nodes[]` / `cluster_max_redirections` | — / `5` | Redis Cluster |
| `connection_is_proxied` | `false` | Set when Redis is behind a proxy (e.g. Envoy) |
| `cloud_authentication.auth_provider` | — | `aws`, `gcp`, `azure` or `oauth` for managed Redis |
| `cloud_authentication.aws_*` | — | `aws_cache_name`, `aws_region`, `aws_is_serverless` (default `true`), `aws_access_key_id`, `aws_secret_access_key`, `aws_assume_role_arn`, `aws_role_session_name` |
| `cloud_authentication.gcp_service_account_json` | — | GCP Memorystore |
| `cloud_authentication.azure_client_id` / `azure_client_secret` / `azure_tenant_id` | — | Azure Cache for Redis (Entra ID) |
| `cloud_authentication.oauth.*` | — | `token_endpoint`, `grant_type` (`client_credentials`), `auth_method` (`client_secret_post`), `client_id`, `client_secret`, `scopes`, `redis_username` or `redis_username_claim`, `ssl_verify`, `timeout` |

## `config.logging`

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `log_statistics` | boolean **R** | `false` | Add MCP metrics to log plugin output |
| `log_payloads` | boolean **R** | `false` | Add request/response bodies to log output. May expose sensitive data |
| `log_audits` | boolean **R** | `false` | Emit audit logs for ACL decisions |

## Version notes

| Version | Change |
| --- | --- |
| 3.12 | Plugin introduced (Enterprise) |
| 3.13 | ACL features; AI MCP OAuth2 treats all traffic on its route as MCP |
| 3.14 | ACL denials return HTTP 403 (previously JSON-RPC error `-32602`) |
| 3.16 | Version this reference was taken from |

## Get the schema yourself

```bash
curl -s -H "Authorization: Bearer $KONNECT_TOKEN" \
  https://us.api.konghq.com/v2/control-planes/<control-plane-id>/core-entities/schemas/plugins/ai-mcp-proxy | jq
```

Self-managed Kong: `curl -s http://localhost:8001/schemas/plugins/ai-mcp-proxy | jq`.
