# Architecture

## 1. Big picture

AI clients speak MCP to Kong. Kong is the MCP server: it turns tool calls into REST calls (or forwards them to a real MCP server) and applies auth, ACLs, rate limits and logging on the way. You manage everything in Konnect.

```mermaid
flowchart LR
    subgraph clients["AI clients"]
      cc["Claude Code"]
      cu["Cursor"]
      ag["Custom agents<br/>(MCP SDK)"]
      in["MCP Inspector"]
    end

    subgraph konnect["Kong Konnect (SaaS)"]
      cp["Control plane<br/>Services, Routes, Plugins,<br/>Consumers, Consumer Groups"]
      an["Analytics / Explorer"]
    end

    subgraph dp["Kong data plane (Serverless, Dedicated Cloud or self-hosted)"]
      direction TB
      auth["Auth<br/>key-auth / OIDC / ai-mcp-oauth2"]
      mcp["AI MCP Proxy<br/>MCP server + ACLs"]
      rl["Rate limiting, transforms,<br/>log plugins"]
      auth --> mcp --> rl
    end

    subgraph upstreams["Upstreams"]
      rest["REST APIs<br/>(e.g. Petstore)"]
      rmcp["Existing MCP servers"]
    end

    ops["You: Konnect UI,<br/>decK, Terraform"] --> cp
    cp == "config push (mTLS)" ==> dp
    dp -. "metrics, logs" .-> an
    clients -- "MCP over Streamable HTTP<br/>POST /petstore" --> auth
    rl -- "REST (conversion modes)" --> rest
    rl -- "MCP (passthrough-listener)" --> rmcp
```

| Layer | Component | Responsibility |
| --- | --- | --- |
| Clients | Claude Code, Cursor, agents | Discover tools (`tools/list`), call them (`tools/call`) |
| Management | Konnect control plane | Stores config; pushes it to data planes; never receives client traffic |
| Runtime | Kong data plane | Runs the plugins and serves the proxy URL |
| MCP | AI MCP Proxy plugin | MCP protocol, sessions, tool catalogue, REST conversion, ACLs |
| Security | key-auth / OIDC / AI MCP OAuth2, rate limiting | Identity, quotas |
| Backends | REST APIs, MCP servers | Do the actual work |
| Observability | Log plugins, Prometheus, OpenTelemetry, Konnect Analytics | MCP metrics, audit logs |

## 2. Inside the data plane: one tool call

```mermaid
sequenceDiagram
    autonumber
    participant C as MCP client
    participant A as Auth plugin
    participant M as AI MCP Proxy
    participant RT as Kong router
    participant U as Upstream REST API

    C->>A: POST /petstore tools/call get-pet-by-id {path_petId: 1}<br/>apikey, mcp-session-id
    A->>A: identify consumer (+ groups)
    A->>M: authenticated MCP request
    M->>M: session check, ACL check (deny > allow)
    M->>RT: internal GET /petstore/pet/1<br/>(client headers forwarded)
    RT->>A: same route: plugins run again
    A->>U: GET /api/v3/pet/1 (strip_path + service path)
    U-->>M: 200 JSON
    M-->>C: result.content[0].text (text/event-stream)
```

Key point: tool calls **re-enter Kong's router**. Tool paths must resolve to a route (use relative paths), and route plugins apply to tool calls as well.

## 3. Mode architectures

### conversion-listener (one API, one endpoint)

```mermaid
flowchart LR
    c["Client"] --> r["Route /petstore<br/>ai-mcp-proxy: conversion-listener<br/>tools: 6"]
    r -- "internal REST via same route" --> r
    r --> s["Service<br/>petstore3.swagger.io/api/v3"]
```

### conversion-only + listener (many APIs, one endpoint)

```mermaid
flowchart LR
    c["Client"] --> l["Route /mcp<br/>listener<br/>server.tag: petstore-tools"]
    l -. "tool catalogue" .-> p1["Route /pets-api<br/>conversion-only<br/>tag: petstore-tools"]
    l -. "tool catalogue" .-> p2["Route /store-api<br/>conversion-only<br/>tag: petstore-tools"]
    l -- "tools/call" --> p1
    l -- "tools/call" --> p2
    p1 --> s1["Pets API"]
    p2 --> s2["Store API"]
```

### passthrough-listener (govern an existing MCP server)

```mermaid
flowchart LR
    c["Client"] --> r["Route /remote-mcp<br/>auth + passthrough-listener<br/>+ rate limiting + logs"]
    r -- "MCP unchanged" --> m["Remote MCP server<br/>(own tools and sessions)"]
```

### OAuth 2.0 layout (3.13+)

```mermaid
flowchart LR
    c["Client"] -- "1. GET .well-known/<br/>oauth-protected-resource" --> o
    c -- "2. login" --> idp["Authorization server<br/>(Keycloak, Okta, Entra ID)"]
    c -- "3. MCP + Bearer token" --> o["Route /petstore-oauth<br/>ai-mcp-oauth2 + listener"]
    o -. "validate token<br/>(introspection / JWKS)" .-> idp
    o -- "tools/call" --> t["Route /petstore-oauth-tools<br/>conversion-only"]
    t --> api["REST API<br/>(X-User-Id from token)"]
```

## 4. Deployment and configuration flow

```mermaid
flowchart LR
    git["Git repo<br/>examples/*.yaml, terraform/"] --> ci["CI or laptop"]
    ci -- "deck gateway sync<br/>(select_tags)" --> cp["Konnect control plane"]
    ci -- "terraform apply" --> cp
    ui["Konnect UI"] --> cp
    cp == "push" ==> dp1["Data plane node 1"]
    cp == "push" ==> dp2["Data plane node N"]
    dp1 & dp2 --- sess[("Sessions:<br/>client-encrypted id<br/>or Redis")]
```

- The **Konnect organization** is chosen by the personal access token; the control plane by name or ID. Orgs can share a display name, so check IDs.
- With several data plane nodes, use `server.session.strategy: client` or `redis` so any node can continue a session.

## 5. Security layers

```mermaid
flowchart TB
    req["Incoming MCP request"] --> l1{"1. Identity<br/>key-auth / OIDC / OAuth2"}
    l1 -- "fail" --> e401["401"]
    l1 -- "ok" --> l2{"2. Rate limit"}
    l2 -- "over" --> e429["429"]
    l2 -- "ok" --> l3{"3. Tool ACL<br/>default_acl / tools[].acl"}
    l3 -- "deny" --> e403["403 + audit log"]
    l3 -- "allow" --> l4["4. Tool call with<br/>forwarded headers"]
    l4 --> up["Upstream<br/>(can trust X-User-Id)"]
```

## 6. Reference deployment used in this repo

| Item | Value |
| --- | --- |
| Konnect region | US (`https://us.api.konghq.com`) |
| Control plane | Serverless API Gateway |
| Kong version | 3.16.0.1 Enterprise |
| MCP endpoint | `https://<proxy-url>/petstore` |
| Upstream | `https://petstore3.swagger.io/api/v3` |
| Clients tested | curl, browser fetch (handshake + `tools/list`) |

## PNG versions

Rendered copies for viewers that don't support Mermaid: [docs/images/](images/).

| Diagram | File |
| --- | --- |
| Big picture | [architecture-overview.png](images/architecture-overview.png) |
| One tool call | [tool-call-sequence.png](images/tool-call-sequence.png) |
| conversion-listener | [mode-conversion-listener.png](images/mode-conversion-listener.png) |
| conversion-only + listener | [mode-aggregation.png](images/mode-aggregation.png) |
| passthrough-listener | [mode-passthrough.png](images/mode-passthrough.png) |
| OAuth 2.0 | [oauth-flow.png](images/oauth-flow.png) |
| Deployment | [deployment-flow.png](images/deployment-flow.png) |
| Security layers | [security-layers.png](images/security-layers.png) |
