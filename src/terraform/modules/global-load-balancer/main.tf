# Global Application Load Balancer that routes all traffic through the global Envoy backend service

# Static IP for the global load balancer
resource "google_compute_global_address" "main" {
  name = "${var.name_prefix}-global-ip"
}

# Main URL Map - routes all traffic to the global Envoy backend service
resource "google_compute_url_map" "main" {
  name            = "${var.name_prefix}-global-urlmap"
  default_service = var.backend_service_id
}

# HTTPS redirect URL map
resource "google_compute_url_map" "redirect_to_https" {
  count = var.enable_ssl ? 1 : 0
  name  = "${var.name_prefix}-global-redirect-urlmap"

  default_url_redirect {
    https_redirect         = true
    redirect_response_code = "MOVED_PERMANENTLY_DEFAULT"
    strip_query            = false
  }
}

# Target HTTP proxy
resource "google_compute_target_http_proxy" "main" {
  name    = "${var.name_prefix}-global-http-proxy"
  url_map = var.enable_ssl ? google_compute_url_map.redirect_to_https[0].id : google_compute_url_map.main.id
}

# Target HTTPS proxy
resource "google_compute_target_https_proxy" "main" {
  count            = var.enable_ssl ? 1 : 0
  name             = "${var.name_prefix}-global-https-proxy"
  url_map          = google_compute_url_map.main.id
  ssl_certificates = [google_compute_managed_ssl_certificate.main[0].id]
}

# SSL certificate
resource "google_compute_managed_ssl_certificate" "main" {
  count = var.enable_ssl ? 1 : 0
  name  = "${var.name_prefix}-global-ssl-cert"

  managed {
    domains = length(var.ssl_domains) > 0 ? var.ssl_domains : [var.domain, "*.${var.domain}"]
  }
}

# Global forwarding rule for HTTPS
resource "google_compute_global_forwarding_rule" "https" {
  count                 = var.enable_ssl ? 1 : 0
  name                  = "${var.name_prefix}-global-https-forwarding-rule"
  ip_protocol           = "TCP"
  load_balancing_scheme = "EXTERNAL_MANAGED"
  port_range            = "443"
  target                = google_compute_target_https_proxy.main[0].id
  ip_address            = google_compute_global_address.main.id
}

# Global forwarding rule for HTTP
resource "google_compute_global_forwarding_rule" "http" {
  name                  = "${var.name_prefix}-global-http-forwarding-rule"
  ip_protocol           = "TCP"
  load_balancing_scheme = "EXTERNAL_MANAGED"
  port_range            = "80"
  target                = google_compute_target_http_proxy.main.id
  ip_address            = google_compute_global_address.main.id
}