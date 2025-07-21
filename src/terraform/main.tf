terraform {
  required_version = ">= 1.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

# Health checks module
module "health_checks" {
  source = "./modules/health-checks"
  
  name_prefix = var.name_prefix
}

# GCS module for tenant mappings
module "gcs" {
  source = "./modules/gcs"
  
  project_id  = var.project_id
  region      = var.region
  name_prefix = var.name_prefix
  shard_names = var.shard_names
}

# Shard modules (already exists in shards.tf, keeping it there)

# Envoy module
module "envoy" {
  source = "./modules/envoy"
  
  name_prefix            = var.name_prefix
  zone                   = var.zone
  shard_names            = var.shard_names
  shard_backends         = module.shard
  gcs_bucket_name        = module.gcs.bucket_name
  service_account_email  = module.gcs.service_account_email
  wasm_filter_path       = "${path.module}/../wasm-filter"
  use_lua_filter         = var.use_lua_filter
  project_id             = var.project_id
}

# Main load balancer module
module "main_load_balancer" {
  source = "./modules/main-load-balancer"
  
  name_prefix             = var.name_prefix
  domain                  = var.domain
  envoy_instance_group_id = module.envoy.instance_group_id
  health_check_id         = module.health_checks.health_check_id
}

# Outputs
output "load_balancer_ip" {
  value       = module.main_load_balancer.load_balancer_ip
  description = "The external IP address of the main load balancer"
}

output "envoy_ip" {
  value       = module.envoy.external_ip
  description = "External IP of the Envoy router"
}

output "ssl_certificate_status" {
  value       = module.main_load_balancer.ssl_certificate_status
  description = "SSL certificate status"
}

output "gcs_bucket" {
  value       = module.gcs.bucket_name
  description = "GCS bucket containing tenant mappings"
}