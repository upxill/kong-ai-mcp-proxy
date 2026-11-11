variable "control_plane_id" {
  description = "Konnect control plane ID (API Gateway -> control plane -> Overview)"
  type        = string
}

variable "mcp_path" {
  description = "Route path that becomes the MCP endpoint"
  type        = string
  default     = "/petstore-tf"
}

variable "proxy_url" {
  description = "Control plane proxy URL, used only for the output"
  type        = string
  default     = "https://<your-proxy-url>"
}
