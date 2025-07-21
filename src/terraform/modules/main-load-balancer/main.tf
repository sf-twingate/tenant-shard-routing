# Main Application Load Balancer that routes all traffic through Envoy

# Static IP for the main load balancer
resource "google_compute_global_address" "main" {
  name = "${var.name_prefix}-main-ip"
}

# Backend service for Envoy
resource "google_compute_backend_service" "envoy_backend" {
  name                  = "${var.name_prefix}-envoy-backend"
  protocol              = "HTTP"
  port_name             = "http"
  timeout_sec           = 30
  load_balancing_scheme = "EXTERNAL_MANAGED"

  backend {
    group           = var.envoy_instance_group_id
    balancing_mode  = "UTILIZATION"
    capacity_scaler = 1.0
  }

  health_checks = [var.health_check_id]
}

# Main URL Map - routes all traffic to Envoy
resource "google_compute_url_map" "main" {
  name            = "${var.name_prefix}-urlmap"
  default_service = google_compute_backend_service.envoy_backend.id
}

# HTTPS redirect URL map
resource "google_compute_url_map" "redirect_to_https" {
  count = var.enable_ssl ? 1 : 0
  name  = "${var.name_prefix}-redirect-urlmap"

  default_url_redirect {
    https_redirect         = true
    redirect_response_code = "MOVED_PERMANENTLY_DEFAULT"
    strip_query            = false
  }
}

# Target HTTP proxy
resource "google_compute_target_http_proxy" "main" {
  name    = "${var.name_prefix}-http-proxy"
  url_map = var.enable_ssl ? google_compute_url_map.redirect_to_https[0].id : google_compute_url_map.main.id
}

# Target HTTPS proxy
resource "google_compute_target_https_proxy" "main" {
  count            = var.enable_ssl ? 1 : 0
  name             = "${var.name_prefix}-https-proxy"
  url_map          = google_compute_url_map.main.id
  ssl_certificates = [google_compute_managed_ssl_certificate.main[0].id]
}

# SSL certificate
resource "google_compute_managed_ssl_certificate" "main" {
  count = var.enable_ssl ? 1 : 0
  name  = "${var.name_prefix}-ssl-cert"

  managed {
    domains = length(var.ssl_domains) > 0 ? var.ssl_domains : [var.domain, "*.${var.domain}"]
  }
}

# Global forwarding rule for HTTPS
resource "google_compute_global_forwarding_rule" "https" {
  count                 = var.enable_ssl ? 1 : 0
  name                  = "${var.name_prefix}-https-forwarding-rule"
  ip_protocol           = "TCP"
  load_balancing_scheme = "EXTERNAL_MANAGED"
  port_range            = "443"
  target                = google_compute_target_https_proxy.main[0].id
  ip_address            = google_compute_global_address.main.id
}

# Global forwarding rule for HTTP
resource "google_compute_global_forwarding_rule" "http" {
  name                  = "${var.name_prefix}-http-forwarding-rule"
  ip_protocol           = "TCP"
  load_balancing_scheme = "EXTERNAL_MANAGED"
  port_range            = "80"
  target                = google_compute_target_http_proxy.main.id
  ip_address            = google_compute_global_address.main.id
}

# Firewall rule for load balancer health checks and proxies
resource "google_compute_firewall" "lb_proxies" {
  name    = "allow-lb-proxies-${var.name_prefix}"
  network = var.network

  allow {
    protocol = "tcp"
    ports    = ["80", "443"]
  }

  source_ranges = [
    "130.211.0.0/22",  # Google Cloud Load Balancer IPs
    "35.191.0.0/16",   # Google Cloud Load Balancer IPs
  ]

  target_tags = ["envoy-router"]
}