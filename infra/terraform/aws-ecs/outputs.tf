output "openai_base_url" {
  description = "The OpenAI-compatible address, inside the VPC."
  value       = "http://${aws_lb.proxy.dns_name}:11535/v1"
}

output "anthropic_base_url" {
  description = "The Anthropic-compatible address, inside the VPC."
  value       = "http://${aws_lb.proxy.dns_name}:11537"
}
