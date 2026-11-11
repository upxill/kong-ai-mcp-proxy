# Defining tools

Each entry in `config.tools` becomes one MCP tool. The tool definition mirrors an OpenAPI operation.

## Anatomy

```yaml
- name: find-pets-by-status            # MCP tool name (optional; see naming)
  description: >                       # REQUIRED. What the AI reads to decide when to call it
    Find pets by status. status must be one of available, pending, sold.
  method: GET                          # GET | PUT | PATCH | POST | DELETE
  path: pet/findByStatus               # relative to the route path (no leading /)
  annotations:
    title: Find pets by status         # human-readable title
    read_only_hint: true               # hints for clients, see below
  parameters:                          # OpenAPI parameter objects
    - name: status
      in: query                        # query | path | header | cookie
      required: true
      description: Pet status to filter by
      schema:
        type: string
        enum: [available, pending, sold]
  acl:                                 # optional per-tool access control
    allow: [readers]
```

## Field reference

| Field | Type | Meaning |
| --- | --- | --- |
| `name` | string | Tool identifier. Used as the MCP tool name (overrides `annotations.title`). In `passthrough-listener`, matches the remote tool name for ACLs |
| `description` | string, **required** | Shown to the AI. Say what it returns and what values arguments accept |
| `method` | `GET` `PUT` `PATCH` `POST` `DELETE` | HTTP method of the REST call. Default: taken from the route |
| `path` | string | REST path. No leading `/` = relative to the route path. Default: taken from the route; required if the route path is not an exact match |
| `host` | string | Host for the call. Default from the route; required if the route host is a wildcard |
| `scheme` | `http` `https` | Override the scheme |
| `headers` | map | Fixed headers for the call (e.g. `Accept: application/json`) |
| `query` | map | Fixed query arguments added to every call |
| `parameters` | JSON (OpenAPI parameters array) | Arguments the AI can pass |
| `request_body` | JSON (OpenAPI requestBody) | Body schema for POST/PUT/PATCH |
| `responses` | JSON (OpenAPI responses) | Validates the upstream response and maps it to `structuredOutput`. Only one success (< 400) response is supported |
| `annotations.title` | string | Human-readable title |
| `annotations.read_only_hint` | boolean | Tool does not change anything |
| `annotations.destructive_hint` | boolean | Tool may delete or overwrite data |
| `annotations.idempotent_hint` | boolean | Repeating the call has no extra effect |
| `annotations.open_world_hint` | boolean | Tool talks to external systems |
| `acl.allow` / `acl.deny` | string arrays | Per-tool access control; see [security.md](security.md) |

## Naming

| You set | Tool name in `tools/list` |
| --- | --- |
| `name: find-pets-by-status` | `find-pets-by-status` |
| only `annotations.title: Find pets by status` | `find-pets-by-status` (slug of the title, verified) |
| neither | a generated name; always set one |

Each tool also gets an `id` like `<plugin-uuid>:<n>`.

## Argument names

Kong prefixes every argument with where it goes (verified in `tools/list`):

| OpenAPI parameter | MCP argument |
| --- | --- |
| `{name: status, in: query}` | `query_status` |
| `{name: petId, in: path}` | `path_petId` |
| `{name: X-Tenant, in: header}` | `header_X-Tenant` (expected; not yet verified) |
| `request_body` | `body` (per Kong docs; not yet verified) |

Example `tools/call`:

```json
{"jsonrpc":"2.0","id":3,"method":"tools/call",
 "params":{"name":"get-pet-by-id","arguments":{"path_petId":1}}}
```

`inputSchema` has `additionalProperties: false`, so unknown arguments are rejected.

## Request bodies

```yaml
- name: add-pet
  description: Add a new pet to the store. Returns the created pet.
  method: POST
  path: pet
  annotations:
    title: Add pet
    destructive_hint: false
  request_body:
    required: true
    content:
      application/json:
        schema:
          type: object
          required: [name, photoUrls]
          properties:
            id: {type: integer}
            name: {type: string}
            status: {type: string, enum: [available, pending, sold]}
            photoUrls: {type: array, items: {type: string}}
```

The AI then passes `{"body": {"name": "Rex", "photoUrls": []}}`. JSON and `application/x-www-form-urlencoded` bodies work; multipart and XML do not.

## Responses and structured output

```yaml
  responses:
    "200":
      description: The pet
      content:
        application/json:
          schema:
            type: object
            properties:
              id: {type: integer}
              name: {type: string}
              status: {type: string}
```

Without `responses`, the upstream body is returned as text in `result.content[0].text`.

## Writing good descriptions

| Weak | Strong |
| --- | --- |
| `Get pets` | `Find pets by status. status must be one of available, pending, sold. Returns a JSON array of pets with id, name, status.` |
| `Delete` | `Permanently delete a pet by ID. Cannot be undone.` (and set `destructive_hint: true`) |

## From an OpenAPI spec

The plugin has no field that imports a spec; tools are listed explicitly. To generate them, map each OpenAPI operation:

| OpenAPI | Tool field |
| --- | --- |
| `operationId` (kebab-cased) | `name` |
| `summary` + `description` | `description` |
| HTTP method | `method` |
| path without the base path, no leading `/` | `path` |
| `parameters` | `parameters` (copy as is) |
| `requestBody` | `request_body` |
| `responses.200` | `responses` |

For Petstore: `operationId: findPetsByStatus`, `GET /pet/findByStatus` → `name: find-pets-by-status`, `method: GET`, `path: pet/findByStatus`.
