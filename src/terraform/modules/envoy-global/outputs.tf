output "global_backend_service_id" {
  description = "ID of the global backend service for Envoy"
  value       = google_compute_backend_service.envoy_global.id
}

output "global_backend_service_self_link" {
  description = "Self link of the global backend service"
  value       = google_compute_backend_service.envoy_global.self_link
}

output "regional_instance_groups" {
  description = "Map of regional instance groups"
  value = {
    for region_key, mig in google_compute_region_instance_group_manager.envoy : 
    region_key => {
      instance_group = mig.instance_group
      region         = mig.region
      self_link      = mig.self_link
      base_name      = mig.base_instance_name
    }
  }
}

output "health_check_self_link" {
  description = "Self link of the health check"
  value       = google_compute_health_check.envoy.self_link
}

output "security_policy_id" {
  description = "ID of the Cloud Armor security policy (if enabled)"
  value       = var.enable_cloud_armor ? google_compute_security_policy.envoy[0].id : null
}

output "regions_deployed" {
  description = "List of regions where Envoy is deployed"
  value       = [for k, v in var.regions : v.region]
}