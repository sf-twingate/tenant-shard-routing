# Dynamic shard creation using the shard module

# Create shards dynamically based on the shard_names list
module "shard" {
  source = "./modules/shard"
  
  for_each = toset(var.shard_names)
  
  shard_name      = each.value
  name_prefix     = var.name_prefix
  region          = var.region
  zone            = var.zone
  health_check_id = module.health_checks.health_check_id
  network         = google_compute_network.main.name
  subnetwork      = google_compute_subnetwork.main.name
}

# Output shard information for debugging
output "shards" {
  description = "Information about all shards"
  value = {
    for name, shard in module.shard :
    name => {
      alb_backend_service = shard.shard_alb_backend_service_name
      alb_ip              = shard.shard_alb_ip
      alb_url             = shard.shard_alb_url
      services            = shard.service_instances
    }
  }
}