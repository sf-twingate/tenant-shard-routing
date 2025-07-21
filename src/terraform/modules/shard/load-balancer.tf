# Application Load Balancer for the shard
# Each shard has its own ALB that handles path-based routing
# Using route_rules instead of path_rule for:
# - Priority-based evaluation (lower numbers = higher priority)
# - Advanced routing capabilities with URL rewriting
# - Future extensibility for header/query-based routing

# Static IP for the shard ALB
resource "google_compute_global_address" "shard" {
  name = "${var.name_prefix}-${var.shard_name}-alb-ip"
}

# URL map for path-based routing within the shard
resource "google_compute_url_map" "shard" {
  name = "${var.name_prefix}-${var.shard_name}-urlmap"
  
  # Default to the default service
  default_service = google_compute_backend_service.default.id

  # Path-based routing rules
  host_rule {
    hosts        = ["*"]
    path_matcher = "${var.shard_name}-paths"
  }

  path_matcher {
    name            = "${var.shard_name}-paths"
    default_service = google_compute_backend_service.default.id

    # Route /foo to foo service with path rewrite
    route_rules {
      priority = 1
      service  = google_compute_backend_service.foo.id
      
      match_rules {
        prefix_match = "/foo"
      }
      
      route_action {
        url_rewrite {
          path_prefix_rewrite = "/"
        }
      }
    }

    # Route /api to api service with path rewrite
    route_rules {
      priority = 2
      service  = google_compute_backend_service.api.id
      
      match_rules {
        prefix_match = "/api"
      }
      
      route_action {
        url_rewrite {
          path_prefix_rewrite = "/"
        }
      }
    }

    # Additional routes can be added here as needed
  }
}

# HTTP proxy for the shard ALB
resource "google_compute_target_http_proxy" "shard" {
  name    = "${var.name_prefix}-${var.shard_name}-http-proxy"
  url_map = google_compute_url_map.shard.id
}

# Forwarding rule for the shard ALB
resource "google_compute_global_forwarding_rule" "shard" {
  name                  = "${var.name_prefix}-${var.shard_name}-forwarding-rule"
  ip_protocol           = "TCP"
  load_balancing_scheme = "EXTERNAL_MANAGED"
  port_range            = "80"
  target                = google_compute_target_http_proxy.shard.id
  ip_address            = google_compute_global_address.shard.id
}

# Network Endpoint Group for connecting Envoy to this shard's ALB
resource "google_compute_global_network_endpoint_group" "shard" {
  name                  = "${var.name_prefix}-${var.shard_name}-neg"
  network_endpoint_type = "INTERNET_IP_PORT"
  default_port          = "80"
}

# Add the shard ALB IP as a network endpoint
resource "google_compute_global_network_endpoint" "shard" {
  global_network_endpoint_group = google_compute_global_network_endpoint_group.shard.id
  ip_address                    = google_compute_global_address.shard.address
  port                          = 80
}

# Backend service that Envoy will use to route to this shard's ALB
resource "google_compute_backend_service" "shard_alb" {
  name                  = "${var.name_prefix}-${var.shard_name}-alb-backend"
  protocol              = "HTTP"
  port_name             = "http"
  timeout_sec           = 30
  load_balancing_scheme = "EXTERNAL_MANAGED"

  backend {
    group = google_compute_global_network_endpoint_group.shard.id
    # Internet NEGs don't support balancing mode configuration
  }

  # No health checks for Internet NEGs
}