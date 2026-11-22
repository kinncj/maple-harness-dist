output "url" {
  description = "The service's address. OpenAI-compatible clients add /v1."
  value       = google_cloud_run_v2_service.proxy.uri
}
