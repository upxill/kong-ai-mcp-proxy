output "mcp_endpoint" {
  value = "${var.proxy_url}${var.mcp_path}"
}

output "claude_code_command" {
  value = "claude mcp add --transport http petstore-tf ${var.proxy_url}${var.mcp_path}"
}
