output "health_check_id" {
  description = "ID of the health check resource"
  value       = google_compute_health_check.default.id
}

output "health_check_self_link" {
  description = "Self link of the health check resource"
  value       = google_compute_health_check.default.self_link
}

output "backend_tags" {
  description = "Firewall tags to apply to backend instances"
  value       = ["${var.name_prefix}-backend", "http-server"]
}

output "envoy_tags" {
  description = "Firewall tags to apply to Envoy instances"
  value       = ["envoy-router"]
}