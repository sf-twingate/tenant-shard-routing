# Outputs for the tenant routing architecture

# Main infrastructure outputs
output "main_load_balancer_ip" {
  description = "Global Load Balancer IP address"
  value       = var.use_global_deployment ? (length(module.main_load_balancer_global) > 0 ? module.main_load_balancer_global[0].load_balancer_ip : "") : (length(module.main_load_balancer) > 0 ? module.main_load_balancer[0].load_balancer_ip : "")
}

output "main_load_balancer_url" {
  description = "URL to access the main load balancer"
  value       = var.use_global_deployment ? (length(module.main_load_balancer_global) > 0 ? "https://${module.main_load_balancer_global[0].load_balancer_ip}" : "") : (length(module.main_load_balancer) > 0 ? "https://${module.main_load_balancer[0].load_balancer_ip}" : "")
}

output "load_balancer_ip" {
  description = "Alias for main_load_balancer_ip"
  value       = var.use_global_deployment ? (length(module.main_load_balancer_global) > 0 ? module.main_load_balancer_global[0].load_balancer_ip : "") : (length(module.main_load_balancer) > 0 ? module.main_load_balancer[0].load_balancer_ip : "")
}

output "envoy_ip" {
  description = "Envoy instance IP (single-region only)"
  value       = var.use_global_deployment ? "" : (length(module.envoy) > 0 ? module.envoy[0].external_ip : "")
}

output "gcs_bucket" {
  description = "GCS bucket name for tenant mappings"
  value       = module.gcs.bucket_name
}

output "name_prefix" {
  description = "Resource name prefix"
  value       = var.name_prefix
}

# Architecture information
output "architecture_flow" {
  description = "Architecture flow diagram"
  value = var.use_global_deployment ? (
    <<-EOT
    Client Request
         ↓
    Global ALB (${length(module.main_load_balancer_global) > 0 ? module.main_load_balancer_global[0].load_balancer_ip : ""})
         ↓
    Envoy Router Clusters (Multi-Region)
         ↓
    Shard ALBs:
    ${join("\n    ", [for name, shard in module.shard : "${name}: ${shard.shard_alb_ip}"])}
         ↓
    Backend Services
    EOT
  ) : (
    <<-EOT
    Client Request
         ↓
    Main ALB (${length(module.main_load_balancer) > 0 ? module.main_load_balancer[0].load_balancer_ip : ""})
         ↓
    Envoy Router (${length(module.envoy) > 0 ? module.envoy[0].external_ip : ""})
         ↓
    Shard ALBs:
    ${join("\n    ", [for name, shard in module.shard : "${name}: ${shard.shard_alb_ip}"])}
         ↓
    Backend Services
    EOT
  )
}

# Instructions for managing tenant mappings
output "tenant_mapping_instructions" {
  description = "How to manage tenant-shard mappings"
  value = <<-EOT
    To add a tenant mapping:
    echo "<shard-name>" | gsutil cp - gs://${module.gcs.bucket_name}/<tenant-name>/shard
    
    Example:
    echo "shard1" | gsutil cp - gs://${module.gcs.bucket_name}/customer1/shard
    echo "shard2" | gsutil cp - gs://${module.gcs.bucket_name}/customer2/shard
  EOT
}