output "instance_id" {
  description = "Envoy instance ID"
  value       = google_compute_instance.envoy_router.id
}

output "instance_self_link" {
  description = "Envoy instance self link"
  value       = google_compute_instance.envoy_router.self_link
}

output "instance_group_id" {
  description = "Envoy instance group ID"
  value       = google_compute_instance_group.envoy.id
}

output "instance_group_self_link" {
  description = "Envoy instance group self link"
  value       = google_compute_instance_group.envoy.self_link
}

output "external_ip" {
  description = "External IP of the Envoy instance"
  value       = google_compute_instance.envoy_router.network_interface[0].access_config[0].nat_ip
}

output "internal_ip" {
  description = "Internal IP of the Envoy instance"
  value       = google_compute_instance.envoy_router.network_interface[0].network_ip
}

output "instance_name" {
  description = "Name of the Envoy instance"
  value       = google_compute_instance.envoy_router.name
}