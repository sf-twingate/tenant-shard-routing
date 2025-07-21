# Network configuration for the tenant routing infrastructure

# VPC Network
resource "google_compute_network" "main" {
  name                    = "${var.name_prefix}-network"
  auto_create_subnetworks = false
  project                 = var.project_id
}

# Service account for Envoy instances
resource "google_service_account" "envoy" {
  account_id   = "${var.name_prefix}-envoy-sa"
  display_name = "Service Account for Envoy instances"
  project      = var.project_id
}

# IAM roles for Envoy service account
resource "google_project_iam_member" "envoy_gcs_reader" {
  project = var.project_id
  role    = "roles/storage.objectViewer"
  member  = "serviceAccount:${google_service_account.envoy.email}"
}

resource "google_project_iam_member" "envoy_logging" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.envoy.email}"
}

resource "google_project_iam_member" "envoy_monitoring" {
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.envoy.email}"
}

resource "google_project_iam_member" "envoy_container_reader" {
  project = var.project_id
  role    = "roles/artifactregistry.reader"
  member  = "serviceAccount:${google_service_account.envoy.email}"
}

# Subnetwork for single-region deployment (used by existing main.tf)
resource "google_compute_subnetwork" "main" {
  name          = "${var.name_prefix}-subnet-${var.region}"
  network       = google_compute_network.main.id
  region        = var.region
  ip_cidr_range = "10.0.0.0/24"
}

# Firewall rules for health checks
resource "google_compute_firewall" "allow_health_checks" {
  name    = "${var.name_prefix}-allow-health-checks"
  network = google_compute_network.main.name

  allow {
    protocol = "tcp"
    ports    = ["80", "443", "8080", "9901"]
  }

  # Google Cloud health check source ranges
  source_ranges = [
    "35.191.0.0/16",
    "130.211.0.0/22"
  ]

  target_tags = ["http-server", "https-server", "envoy-router"]
}

# Firewall rule for internal communication
resource "google_compute_firewall" "allow_internal" {
  name    = "${var.name_prefix}-allow-internal"
  network = google_compute_network.main.name

  allow {
    protocol = "tcp"
    ports    = ["0-65535"]
  }

  allow {
    protocol = "udp"
    ports    = ["0-65535"]
  }

  allow {
    protocol = "icmp"
  }

  source_ranges = [
    "10.0.0.0/8"
  ]
}

# Firewall rule for HTTP/HTTPS from load balancers
resource "google_compute_firewall" "allow_lb" {
  name    = "${var.name_prefix}-allow-lb"
  network = google_compute_network.main.name

  allow {
    protocol = "tcp"
    ports    = ["80", "443", "8080"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["http-server", "https-server", "envoy-router"]
}

# Cloud Router for NAT (if instances don't need public IPs)
resource "google_compute_router" "main" {
  name    = "${var.name_prefix}-router"
  region  = var.region
  network = google_compute_network.main.id
}

# Cloud NAT for outbound internet access
resource "google_compute_router_nat" "main" {
  name                               = "${var.name_prefix}-nat"
  router                             = google_compute_router.main.name
  region                             = var.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"

  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}

# Locals for shard configuration
locals {
  # Generate shard backend URLs from module outputs
  shard_backends = {
    for name, shard in module.shard :
    name => shard.shard_alb_url
  }
  
  shard_names = var.shard_names
}