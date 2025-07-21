# Global Envoy deployment across multiple regions

locals {
  # Flatten regions configuration for easier iteration
  region_zones = flatten([
    for region_key, region in var.regions : [
      for zone in region.zones : {
        region_key = region_key
        region     = region.region
        zone       = zone
      }
    ]
  ])
  
  # Create envoy config template
  envoy_config = var.use_lua_filter ? templatefile("${path.module}/../envoy/templates/envoy-lua.yaml.tpl", {
    shard_names     = var.shard_names
    shard_backends  = var.shard_backends
    gcs_bucket_name = var.gcs_bucket_name
    default_shard   = var.shard_names[0]
  }) : templatefile("${path.module}/../envoy/templates/envoy-wasm.yaml.tpl", {
    shard_names     = var.shard_names
    shard_backends  = var.shard_backends
    gcs_bucket_name = var.gcs_bucket_name
    default_shard   = var.shard_names[0]
  })
}

# Instance template for Envoy (shared across all regions)
resource "google_compute_instance_template" "envoy" {
  name_prefix  = "${var.name_prefix}-envoy-global-"
  machine_type = "e2-medium" # Will be overridden by regional configs

  disk {
    source_image = var.use_optimized_image ? (
      var.use_lua_filter ? "${var.project_id}/envoy-lua-optimized" : "${var.project_id}/envoy-wasm-optimized"
    ) : "ubuntu-os-cloud/ubuntu-2204-lts"
    auto_delete  = true
    boot         = true
  }

  network_interface {
    network    = var.network
    # Use the us-central1 subnet as default (will be overridden by regional configs)
    subnetwork = "${var.subnetwork_prefix}-us-central1"
    
    access_config {
      # Ephemeral public IP for outbound connections
    }
  }

  metadata = {
    startup-script = var.use_lua_filter ? templatefile("${path.module}/../envoy/templates/envoy-lua-startup.sh.tpl", {
      envoy_config    = local.envoy_config
      gcs_bucket_name = var.gcs_bucket_name
      default_shard   = var.shard_names[0]
      shard_names     = var.shard_names
      shard_backends  = var.shard_backends
      project_id      = var.project_id
    }) : var.use_optimized_image ? templatefile("${path.module}/../envoy/templates/envoy-wasm-startup-optimized.sh.tpl", {
      envoy_config    = local.envoy_config
      shard_names     = var.shard_names
      shard_backends  = var.shard_backends
      project_id      = var.project_id
      gcs_bucket_name = var.gcs_bucket_name
    }) : templatefile("${path.module}/../envoy/templates/envoy-wasm-startup.sh.tpl", {
      envoy_config    = local.envoy_config
      shard_names     = var.shard_names
      shard_backends  = var.shard_backends
      project_id      = var.project_id
      gcs_bucket_name = var.gcs_bucket_name
    })
  }

  tags = ["http-server", "https-server", "envoy-router"]

  service_account {
    email  = var.service_account_email
    scopes = ["cloud-platform"]
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Regional instance templates (override machine type and subnetwork)
resource "google_compute_instance_template" "envoy_regional" {
  for_each = var.regions

  name_prefix  = "${var.name_prefix}-envoy-${replace(each.key, "_", "-")}-"
  machine_type = each.value.machine_type
  region       = each.value.region

  disk {
    source_image = var.use_optimized_image ? (
      var.use_lua_filter ? "${var.project_id}/envoy-lua-optimized" : "${var.project_id}/envoy-wasm-optimized"
    ) : "ubuntu-os-cloud/ubuntu-2204-lts"
    auto_delete  = true
    boot         = true
  }

  network_interface {
    network    = var.network
    subnetwork = "${var.subnetwork_prefix}-${each.value.region}"
    
    access_config {
      # Ephemeral public IP
    }
  }

  metadata = {
    startup-script = var.use_lua_filter ? templatefile("${path.module}/../envoy/templates/envoy-lua-startup.sh.tpl", {
      envoy_config    = local.envoy_config
      gcs_bucket_name = var.gcs_bucket_name
      default_shard   = var.shard_names[0]
      shard_names     = var.shard_names
      shard_backends  = var.shard_backends
      project_id      = var.project_id
    }) : var.use_optimized_image ? templatefile("${path.module}/../envoy/templates/envoy-wasm-startup-optimized.sh.tpl", {
      envoy_config    = local.envoy_config
      shard_names     = var.shard_names
      shard_backends  = var.shard_backends
      project_id      = var.project_id
      gcs_bucket_name = var.gcs_bucket_name
    }) : templatefile("${path.module}/../envoy/templates/envoy-wasm-startup.sh.tpl", {
      envoy_config    = local.envoy_config
      shard_names     = var.shard_names
      shard_backends  = var.shard_backends
      project_id      = var.project_id
      gcs_bucket_name = var.gcs_bucket_name
    })
  }

  tags = ["http-server", "https-server", "envoy-router"]

  service_account {
    email  = var.service_account_email
    scopes = ["cloud-platform"]
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Regional managed instance groups
resource "google_compute_region_instance_group_manager" "envoy" {
  for_each = var.regions

  name               = "${var.name_prefix}-envoy-${replace(each.key, "_", "-")}-rmig"
  base_instance_name = "${var.name_prefix}-envoy-${replace(each.key, "_", "-")}"
  region             = each.value.region

  version {
    instance_template = google_compute_instance_template.envoy_regional[each.key].id
  }

  # Let autoscaler manage the target size
  # target_size = each.value.instance_count

  distribution_policy_zones = each.value.zones

  named_port {
    name = "http"
    port = 80
  }

  auto_healing_policies {
    health_check      = google_compute_health_check.envoy.id
    initial_delay_sec = 300
  }

  update_policy {
    type                           = "PROACTIVE"
    minimal_action                 = "REPLACE"
    most_disruptive_allowed_action = "REPLACE"
    max_surge_fixed                = 3
    max_unavailable_fixed          = 0
    replacement_method             = "SUBSTITUTE"
  }
}

# Regional autoscalers
resource "google_compute_region_autoscaler" "envoy" {
  for_each = var.regions

  name   = "${var.name_prefix}-envoy-${replace(each.key, "_", "-")}-autoscaler"
  region = each.value.region
  target = google_compute_region_instance_group_manager.envoy[each.key].id

  autoscaling_policy {
    min_replicas    = var.min_instances_per_region
    max_replicas    = var.max_instances_per_region
    cooldown_period = 60

    cpu_utilization {
      target = 0.6
    }

    load_balancing_utilization {
      target = 0.8
    }
  }
}

# Health check for Envoy instances
resource "google_compute_health_check" "envoy" {
  name = "${var.name_prefix}-envoy-health"

  http_health_check {
    port         = 80
    request_path = "/health"
  }

  check_interval_sec  = 10
  timeout_sec         = 5
  healthy_threshold   = 2
  unhealthy_threshold = 3
}

# Global backend service with multi-region backends
resource "google_compute_backend_service" "envoy_global" {
  name                  = "${var.name_prefix}-envoy-global-backend"
  protocol              = "HTTP"
  port_name             = "http"
  timeout_sec           = 30
  load_balancing_scheme = "EXTERNAL_MANAGED"
  
  depends_on = [google_compute_health_check.envoy]

  dynamic "backend" {
    for_each = var.regions
    content {
      group           = google_compute_region_instance_group_manager.envoy[backend.key].instance_group
      balancing_mode  = "UTILIZATION"
      capacity_scaler = 1.0
    }
  }

  health_checks = [google_compute_health_check.envoy.id]

  # Enable Cloud CDN for static content caching
  dynamic "cdn_policy" {
    for_each = var.enable_cdn ? [1] : []
    content {
      cache_mode = "CACHE_ALL_STATIC"
      default_ttl = 3600
      max_ttl     = 86400
      
      cache_key_policy {
        include_host = true
        include_protocol = true
        include_query_string = false
      }
    }
  }

  # Enable session affinity for consistent routing (optional)
  session_affinity = "CLIENT_IP"
  
  # Connection draining timeout
  connection_draining_timeout_sec = 300

  # Enable logging
  log_config {
    enable      = true
    sample_rate = 1.0
  }

  # Attach security policy if enabled
  security_policy = var.enable_cloud_armor ? google_compute_security_policy.envoy[0].self_link : null
}

# Cloud Armor security policy (DDoS protection)
resource "google_compute_security_policy" "envoy" {
  count = var.enable_cloud_armor ? 1 : 0
  
  name = "${var.name_prefix}-envoy-security-policy"

  # Default rule
  rule {
    action   = "allow"
    priority = "2147483647"
    
    match {
      versioned_expr = "SRC_IPS_V1"
      
      config {
        src_ip_ranges = ["*"]
      }
    }
    
    description = "Default allow all rule"
  }

  # Rate limiting rule
  rule {
    action   = "rate_based_ban"
    priority = "1000"
    
    match {
      versioned_expr = "SRC_IPS_V1"
      
      config {
        src_ip_ranges = ["*"]
      }
    }
    
    rate_limit_options {
      conform_action = "allow"
      exceed_action  = "deny(429)"
      
      rate_limit_threshold {
        count        = 100
        interval_sec = 60
      }
      
      ban_duration_sec = 600
    }
    
    description = "Rate limiting rule"
  }
}

# Attach security policy to backend service
# Security policy is attached directly to backend service

# Outputs
output "backend_service_id" {
  value = google_compute_backend_service.envoy_global.id
}

output "health_check_id" {
  value = google_compute_health_check.envoy.id
}

output "instance_groups" {
  value = {
    for k, v in google_compute_region_instance_group_manager.envoy : 
    k => {
      instance_group = v.instance_group
      region         = v.region
      self_link      = v.self_link
    }
  }
}