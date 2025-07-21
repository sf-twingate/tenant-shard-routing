# Outputs for the tenant routing architecture

# Main infrastructure outputs
output "main_load_balancer_ip" {
  description = "Global Load Balancer IP address"
  value       = module.main_load_balancer.load_balancer_ip
}

output "main_load_balancer_url" {
  description = "URL to access the main load balancer"
  value       = "https://${module.main_load_balancer.load_balancer_ip}"
}

# Architecture information
output "architecture_flow" {
  description = "Architecture flow diagram"
  value = <<-EOT
    Client Request
         ↓
    Main ALB (${module.main_load_balancer.load_balancer_ip})
         ↓
    Envoy Router (${module.envoy.external_ip})
         ↓
    Shard ALBs:
    ${join("\n    ", [for name, shard in module.shard : "${name}: ${shard.shard_alb_ip}"])}
         ↓
    Backend Services
  EOT
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