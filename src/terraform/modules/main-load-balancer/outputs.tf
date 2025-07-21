output "load_balancer_ip" {
  description = "The external IP address of the main load balancer"
  value       = google_compute_global_address.main.address
}

output "load_balancer_ip_self_link" {
  description = "Self link of the load balancer IP"
  value       = google_compute_global_address.main.self_link
}

output "backend_service_id" {
  description = "ID of the Envoy backend service"
  value       = google_compute_backend_service.envoy_backend.id
}

output "backend_service_self_link" {
  description = "Self link of the Envoy backend service"
  value       = google_compute_backend_service.envoy_backend.self_link
}

output "ssl_certificate_status" {
  description = "SSL certificate status"
  value = var.enable_ssl ? "Certificate provisioning for ${join(", ", google_compute_managed_ssl_certificate.main[0].managed[0].domains)}" : "SSL disabled"
}

output "http_url" {
  description = "HTTP URL for accessing the load balancer"
  value       = "http://${google_compute_global_address.main.address}"
}

output "https_url" {
  description = "HTTPS URL for accessing the load balancer"
  value       = var.enable_ssl ? "https://${google_compute_global_address.main.address}" : "N/A - SSL disabled"
}