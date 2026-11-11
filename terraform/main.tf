terraform {
  required_providers {
    konnect = { source = "kong/konnect" }
  }
}

provider "konnect" {
  server_url = "https://us.api.konghq.com" # token from env KONNECT_TOKEN
}

resource "konnect_gateway_service" "petstore" {
  control_plane_id = var.control_plane_id
  name             = "petstore-tf"
  protocol         = "https"
  host             = "petstore3.swagger.io"
  port             = 443
  path             = "/api/v3"
  tags             = ["mcp-terraform"]
}

resource "konnect_gateway_route" "petstore_mcp" {
  control_plane_id = var.control_plane_id
  name             = "petstore-tf-mcp"
  paths            = [var.mcp_path]
  strip_path       = true
  service          = { id = konnect_gateway_service.petstore.id }
  tags             = ["mcp-terraform"]
}

resource "konnect_gateway_plugin_ai_mcp_proxy" "petstore" {
  control_plane_id = var.control_plane_id
  enabled          = true
  route            = { id = konnect_gateway_route.petstore_mcp.id }
  tags             = ["mcp-terraform"]

  config = {
    mode = "conversion-listener"
    server = {
      timeout = 60000
    }
    logging = {
      log_statistics = true
      log_payloads   = false
      log_audits     = false
    }
    tools = [
      {
        name        = "find-pets-by-status"
        description = "Find pets by status. status must be one of available, pending, sold."
        method      = "GET"
        path        = "pet/findByStatus"
        annotations = { title = "Find pets by status", read_only_hint = true }
        # parameters is a JSON field in the schema
        parameters = jsonencode([{
          name     = "status"
          in       = "query"
          required = true
          schema   = { type = "string", enum = ["available", "pending", "sold"] }
        }])
      },
      {
        name        = "get-pet-by-id"
        description = "Get a single pet by its numeric ID."
        method      = "GET"
        path        = "pet/{petId}"
        annotations = { title = "Get pet by ID", read_only_hint = true }
        parameters = jsonencode([{
          name     = "petId"
          in       = "path"
          required = true
          schema   = { type = "integer" }
        }])
      },
      {
        name        = "get-store-inventory"
        description = "Return pet inventory counts grouped by status."
        method      = "GET"
        path        = "store/inventory"
        annotations = { title = "Get store inventory", read_only_hint = true }
      },
    ]
  }
}
