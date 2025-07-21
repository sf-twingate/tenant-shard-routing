output "load_balancer_ip" {
  description = "Global load balancer IP address"
  value       = google_compute_global_address.main.address
}

output "load_balancer_self_link" {
  description = "Self link of the global load balancer address"
  value       = google_compute_global_address.main.self_link
}