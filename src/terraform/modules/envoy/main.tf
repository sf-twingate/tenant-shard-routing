# Generate Envoy configuration dynamically based on shards
locals {
  envoy_config = var.use_lua_filter ? templatefile("${path.module}/templates/envoy-lua.yaml.tpl", {
    shard_names         = var.shard_names
    shard_backends      = var.shard_backends
    gcs_bucket_name     = var.gcs_bucket_name
    default_shard       = var.shard_names[0]  # First shard as default
  }) : templatefile("${path.module}/templates/envoy-wasm.yaml.tpl", {
    shard_names         = var.shard_names
    shard_backends      = var.shard_backends
    gcs_bucket_name     = var.gcs_bucket_name
    default_shard       = var.shard_names[0]  # First shard as default
  })
}

# Envoy router instance
resource "google_compute_instance" "envoy_router" {
  name         = "${var.name_prefix}-envoy"
  machine_type = var.machine_type
  zone         = var.zone

  boot_disk {
    initialize_params {
      image = var.use_optimized_image ? (
        var.use_lua_filter ? "${var.project_id}/envoy-lua-optimized" : "${var.project_id}/envoy-wasm-optimized"
      ) : "ubuntu-os-cloud/ubuntu-2204-lts"
    }
  }

  network_interface {
    network    = var.network
    subnetwork = var.subnetwork
    access_config {
      # Ephemeral public IP
    }
  }

  metadata = {
    startup-script = var.use_lua_filter ? templatefile("${path.module}/templates/envoy-lua-startup.sh.tpl", {
      envoy_config   = local.envoy_config
      gcs_bucket_name = var.gcs_bucket_name
      default_shard   = var.shard_names[0]
      shard_names     = var.shard_names
      shard_backends  = var.shard_backends
      project_id      = var.project_id
    }) : var.use_optimized_image ? templatefile("${path.module}/templates/envoy-wasm-startup-optimized.sh.tpl", {
      envoy_config    = local.envoy_config
      shard_names     = var.shard_names
      shard_backends  = var.shard_backends
      project_id      = var.project_id
      gcs_bucket_name = var.gcs_bucket_name
    }) : templatefile("${path.module}/templates/envoy-wasm-startup.sh.tpl", {
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
}

# Instance group for Envoy
resource "google_compute_instance_group" "envoy" {
  name = "${var.name_prefix}-envoy-ig"
  zone = var.zone

  instances = [google_compute_instance.envoy_router.id]

  named_port {
    name = "http"
    port = "80"
  }
}