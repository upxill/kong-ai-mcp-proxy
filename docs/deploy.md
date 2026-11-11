# Deploying

Four ways to create the same thing. Pick one per environment and stick with it; mixing decK and Terraform on the same entities causes drift.

## Before you start: org, token, control plane

| Check | How |
| --- | --- |
| Which Konnect org | Profile → Switch organization. Note the org **ID**; orgs can share a name |
| Token belongs to that org | Create the personal access token while signed in to it. `deck gateway ping --konnect-addr https://us.api.konghq.com --konnect-token $KONNECT_TOKEN` shows the org |
| Control plane name | API Gateway → control plane → Overview |
| Proxy URL | Same page; this is what clients call |

## Konnect UI

1. **API Gateway** → control plane → **Gateway services** → **New gateway service** → Full URL `https://petstore3.swagger.io/api/v3`, name `petstore`.
2. **Routes** → **New route** → name `petstore-mcp`, service `petstore`, path `/petstore`.
3. Route → **Plugins** → **New plugin** → **AI MCP Proxy**:
   - Mode `conversion-listener`
   - Tools → add each tool: description, method, path (relative, e.g. `pet/findByStatus`), parameters (JSON array), annotations
   - Server → timeout `60000`
   - Logging → statistics on
4. **Save**. Check it appears under Plugins as **AI MCP Proxy · Route · Enabled**.

## decK (recommended)

```bash
brew install kong/deck/deck
export KONNECT_TOKEN="kpat_..."
FLAGS="--konnect-addr https://us.api.konghq.com --konnect-token $KONNECT_TOKEN --konnect-control-plane-name serverless-api-gateway-demo"

deck file validate examples/01-conversion-listener-petstore.yaml   # offline syntax check
deck gateway diff  examples/01-conversion-listener-petstore.yaml $FLAGS
deck gateway sync  examples/01-conversion-listener-petstore.yaml $FLAGS
deck gateway dump  $FLAGS --select-tag petstore-mcp -o current.yaml   # export what's live
```

- Every example has `_info.select_tags`; `sync` only creates, updates or deletes entities with that tag.
- Without `select_tags`, `sync` **deletes everything not in the file**.
- Secrets: `${{ env "DECK_NAME" }}` reads `DECK_NAME` from the environment.

To remove an example: `deck gateway reset $FLAGS --select-tag petstore-mcp`.

## Terraform

See [terraform/](../terraform/). Resource: `konnect_gateway_plugin_ai_mcp_proxy`.

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
export KONNECT_TOKEN="kpat_..."
terraform init && terraform validate && terraform plan && terraform apply
```

## Konnect API

```bash
CP=<control-plane-id>
API=https://us.api.konghq.com/v2/control-planes/$CP/core-entities

curl -s -X POST $API/routes/<route-id>/plugins \
  -H "Authorization: Bearer $KONNECT_TOKEN" -H "Content-Type: application/json" \
  -d '{
    "name": "ai-mcp-proxy",
    "config": {
      "mode": "conversion-listener",
      "logging": {"log_statistics": true, "log_payloads": false, "log_audits": false},
      "tools": [{
        "name": "get-store-inventory",
        "description": "Return pet inventory counts grouped by status.",
        "method": "GET",
        "path": "store/inventory"
      }]
    }
  }'
```

Self-managed Kong uses the Admin API the same way: `POST http://localhost:8001/routes/<route>/plugins`.

## Kubernetes (Kong Ingress Controller)

```yaml
apiVersion: configuration.konghq.com/v1
kind: KongPlugin
metadata:
  name: petstore-mcp
plugin: ai-mcp-proxy
config:
  mode: conversion-listener
  logging: {log_statistics: true, log_payloads: false, log_audits: false}
  tools:
    - name: get-store-inventory
      description: Return pet inventory counts grouped by status.
      method: GET
      path: store/inventory
```

Annotate the Ingress or HTTPRoute with `konghq.com/plugins: petstore-mcp`.
