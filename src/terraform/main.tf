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

# Network and IAM resources are in network.tf

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
  
  # Only create if not using global deployment
  count = var.use_global_deployment ? 0 : 1
  
  name_prefix            = var.name_prefix
  zone                   = var.zone
  network                = google_compute_network.main.name
  subnetwork             = google_compute_subnetwork.main.name
  shard_names            = var.shard_names
  shard_backends         = module.shard
  gcs_bucket_name        = module.gcs.bucket_name
  service_account_email  = google_service_account.envoy.email
  wasm_filter_path       = "${path.module}/../wasm-filter"
  use_lua_filter         = var.use_lua_filter
  project_id             = var.project_id
}

# Main load balancer module (single-region)
module "main_load_balancer" {
  source = "./modules/main-load-balancer"
  
  # Only create if not using global deployment
  count = var.use_global_deployment ? 0 : 1
  
  name_prefix             = var.name_prefix
  domain                  = var.domain
  network                 = google_compute_network.main.name
  envoy_instance_group_id = module.envoy[0].instance_group_id
  health_check_id         = module.health_checks.health_check_id
}

# Global Envoy deployment module
module "envoy_global" {
  source = "./modules/envoy-global"
  
  # Only create if using global deployment
  count = var.use_global_deployment ? 1 : 0

  name_prefix          = var.name_prefix
  project_id           = var.project_id
  network              = google_compute_network.main.name
  subnetwork_prefix    = "${var.name_prefix}-subnet"
  service_account_email = google_service_account.envoy.email

  # Deploy Envoy in multiple regions
  regions = {
    us_central = {
      region         = "us-central1"
      zones          = ["us-central1-a", "us-central1-b", "us-central1-c"]
      instance_count = 3
      machine_type   = "e2-medium"
    }
    europe_west = {
      region         = "europe-west1"
      zones          = ["europe-west1-b", "europe-west1-c", "europe-west1-d"]
      instance_count = 3
      machine_type   = "e2-medium"
    }
    asia_southeast = {
      region         = "asia-southeast1"
      zones          = ["asia-southeast1-a", "asia-southeast1-b", "asia-southeast1-c"]
      instance_count = 3
      machine_type   = "e2-medium"
    }
    us_east = {
      region         = "us-east1"
      zones          = ["us-east1-b", "us-east1-c", "us-east1-d"]
      instance_count = 2
      machine_type   = "e2-medium"
    }
    australia = {
      region         = "australia-southeast1"
      zones          = ["australia-southeast1-a", "australia-southeast1-b", "australia-southeast1-c"]
      instance_count = 2
      machine_type   = "e2-small"
    }
  }

  # Autoscaling configuration
  min_instances_per_region = 2
  max_instances_per_region = 10

  # Shard configuration
  shard_names    = var.shard_names
  shard_backends = module.shard
  gcs_bucket_name = module.gcs.bucket_name

  # Use Lua filter by default
  use_lua_filter   = var.use_lua_filter
  wasm_filter_path = var.use_lua_filter ? "" : "${path.module}/../wasm-filter"

  # Enable security features
  enable_cdn         = true
  enable_cloud_armor = true
}

# Main load balancer module (global)
module "main_load_balancer_global" {
  source = "./modules/global-load-balancer"
  
  # Only create if using global deployment
  count = var.use_global_deployment ? 1 : 0

  name_prefix        = var.name_prefix
  domain             = var.domain
  backend_service_id = module.envoy_global[0].global_backend_service_id
  enable_ssl         = var.enable_ssl
  ssl_domains        = var.ssl_certificate_domains
}

# Create regional subnetworks for Envoy (excluding us-central1 which is created in network.tf)
resource "google_compute_subnetwork" "envoy_regional" {
  # Only create if using global deployment
  for_each = var.use_global_deployment ? {
    "europe-west1"          = "10.1.0.0/24"
    "asia-southeast1"       = "10.2.0.0/24"
    "us-east1"              = "10.3.0.0/24"
    "australia-southeast1"  = "10.4.0.0/24"
  } : {}

  name          = "${var.name_prefix}-subnet-${each.key}"
  network       = google_compute_network.main.id
  region        = each.key
  ip_cidr_range = each.value
}

# Output global Envoy information
output "envoy_global_info" {
  value = var.use_global_deployment ? {
    backend_service_id = module.envoy_global[0].global_backend_service_id
    regions_deployed   = module.envoy_global[0].regions_deployed
    instance_groups    = module.envoy_global[0].regional_instance_groups
  } : null
}

