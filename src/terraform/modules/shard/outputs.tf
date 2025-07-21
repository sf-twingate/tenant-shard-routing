output "shard_alb_backend_service_id" {
  description = "The backend service ID for routing to the shard ALB"
  value       = google_compute_backend_service.shard_alb.id
}

output "shard_alb_backend_service_name" {
  description = "The backend service name for routing to the shard ALB"
  value       = google_compute_backend_service.shard_alb.name
}

output "shard_alb_ip" {
  description = "The external IP address of the shard ALB"
  value       = google_compute_global_address.shard.address
}

output "shard_alb_url" {
  description = "The URL to access the shard ALB"
  value       = "http://${google_compute_global_address.shard.address}"
}

output "service_instances" {
  description = "Map of service names to instance IPs"
  value = {
    default = {
      internal_ip = google_compute_instance.default.network_interface[0].network_ip
      external_ip = try(google_compute_instance.default.network_interface[0].access_config[0].nat_ip, null)
    }
    foo = {
      internal_ip = google_compute_instance.foo.network_interface[0].network_ip
      external_ip = try(google_compute_instance.foo.network_interface[0].access_config[0].nat_ip, null)
    }
    api = {
      internal_ip = google_compute_instance.api.network_interface[0].network_ip
      external_ip = try(google_compute_instance.api.network_interface[0].access_config[0].nat_ip, null)
    }
  }
}