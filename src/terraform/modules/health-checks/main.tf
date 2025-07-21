# Health check for backend services
resource "google_compute_health_check" "default" {
  name               = "${var.name_prefix}-health-check"
  check_interval_sec = var.health_check_interval
  timeout_sec        = var.health_check_timeout
  
  http_health_check {
    port         = var.health_check_port
    request_path = var.health_check_path
  }
}

# Firewall rules for health checks from Google Load Balancer IPs
resource "google_compute_firewall" "health_checks" {
  name    = "allow-health-checks-${var.name_prefix}"
  network = var.network

  allow {
    protocol = "tcp"
    ports    = [tostring(var.health_check_port)]
  }

  source_ranges = [
    "35.191.0.0/16",  # Google Cloud health check IPs
    "130.211.0.0/22"  # Google Cloud health check IPs
  ]
  
  target_tags = ["${var.name_prefix}-backend", "envoy-router"]
}

# Firewall rule for HTTP traffic
resource "google_compute_firewall" "http" {
  name    = "allow-http-${var.name_prefix}"
  network = var.network

  allow {
    protocol = "tcp"
    ports    = ["80"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["http-server", "${var.name_prefix}-backend"]
}