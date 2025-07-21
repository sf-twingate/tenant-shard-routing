# Backend instances for the shard

# Default service instance
resource "google_compute_instance" "default" {
  name         = "${var.name_prefix}-${var.shard_name}-default"
  machine_type = "e2-micro"
  zone         = var.zone

  boot_disk {
    initialize_params {
      image = "ubuntu-os-cloud/ubuntu-2204-lts"
    }
  }

  network_interface {
    network    = var.network
    subnetwork = var.subnetwork
    access_config {
      # Ephemeral public IP
    }
  }

  metadata_startup_script = <<-EOF
    #!/bin/bash
    apt-get update
    apt-get install -y nginx
    
    # Create a simple response page
    cat > /var/www/html/index.html <<HTML
    <!DOCTYPE html>
    <html>
    <head><title>${var.shard_name} - default</title></head>
    <body>
      <h1>Backend Response</h1>
      <p>Shard: ${var.shard_name}</p>
      <p>Service: default</p>
      <p>Path: /</p>
    </body>
    </html>
HTML
    
    # Health check endpoint
    echo "OK" > /var/www/html/health
    
    systemctl restart nginx
  EOF

  tags = ["http-server", "${var.name_prefix}-backend"]
}

# Foo service instance
resource "google_compute_instance" "foo" {
  name         = "${var.name_prefix}-${var.shard_name}-foo"
  machine_type = "e2-micro"
  zone         = var.zone

  boot_disk {
    initialize_params {
      image = "ubuntu-os-cloud/ubuntu-2204-lts"
    }
  }

  network_interface {
    network    = var.network
    subnetwork = var.subnetwork
    access_config {
      # Ephemeral public IP
    }
  }

  metadata_startup_script = <<-EOF
    #!/bin/bash
    apt-get update
    apt-get install -y nginx
    
    # Create a simple response page
    cat > /var/www/html/index.html <<HTML
    <!DOCTYPE html>
    <html>
    <head><title>${var.shard_name} - foo</title></head>
    <body>
      <h1>Backend Response</h1>
      <p>Shard: ${var.shard_name}</p>
      <p>Service: foo</p>
      <p>Path: /foo (rewritten to /)</p>
    </body>
    </html>
HTML
    
    # Health check endpoint
    echo "OK" > /var/www/html/health
    
    systemctl restart nginx
  EOF

  tags = ["http-server", "${var.name_prefix}-backend"]
}

# API service instance
resource "google_compute_instance" "api" {
  name         = "${var.name_prefix}-${var.shard_name}-api"
  machine_type = "e2-micro"
  zone         = var.zone

  boot_disk {
    initialize_params {
      image = "ubuntu-os-cloud/ubuntu-2204-lts"
    }
  }

  network_interface {
    network    = var.network
    subnetwork = var.subnetwork
    access_config {
      # Ephemeral public IP
    }
  }

  metadata_startup_script = <<-EOF
    #!/bin/bash
    apt-get update
    apt-get install -y nginx
    
    # Create a simple response page
    cat > /var/www/html/index.html <<HTML
    <!DOCTYPE html>
    <html>
    <head><title>${var.shard_name} - api</title></head>
    <body>
      <h1>Backend Response</h1>
      <p>Shard: ${var.shard_name}</p>
      <p>Service: api</p>
      <p>Path: /api (rewritten to /)</p>
    </body>
    </html>
HTML
    
    # Health check endpoint
    echo "OK" > /var/www/html/health
    
    systemctl restart nginx
  EOF

  tags = ["http-server", "${var.name_prefix}-backend"]
}

# Instance groups
resource "google_compute_instance_group" "default" {
  name = "${var.name_prefix}-${var.shard_name}-default-ig"
  zone = var.zone

  instances = [google_compute_instance.default.id]

  named_port {
    name = "http"
    port = "80"
  }
}

resource "google_compute_instance_group" "foo" {
  name = "${var.name_prefix}-${var.shard_name}-foo-ig"
  zone = var.zone

  instances = [google_compute_instance.foo.id]

  named_port {
    name = "http"
    port = "80"
  }
}

resource "google_compute_instance_group" "api" {
  name = "${var.name_prefix}-${var.shard_name}-api-ig"
  zone = var.zone

  instances = [google_compute_instance.api.id]

  named_port {
    name = "http"
    port = "80"
  }
}

# Backend services
resource "google_compute_backend_service" "default" {
  name                  = "${var.name_prefix}-${var.shard_name}-default-backend"
  protocol              = "HTTP"
  port_name             = "http"
  timeout_sec           = 30
  load_balancing_scheme = "EXTERNAL_MANAGED"

  backend {
    group           = google_compute_instance_group.default.id
    balancing_mode  = "UTILIZATION"
    capacity_scaler = 1.0
  }

  health_checks = [var.health_check_id]
}

resource "google_compute_backend_service" "foo" {
  name                  = "${var.name_prefix}-${var.shard_name}-foo-backend"
  protocol              = "HTTP"
  port_name             = "http"
  timeout_sec           = 30
  load_balancing_scheme = "EXTERNAL_MANAGED"

  backend {
    group           = google_compute_instance_group.foo.id
    balancing_mode  = "UTILIZATION"
    capacity_scaler = 1.0
  }

  health_checks = [var.health_check_id]
}

resource "google_compute_backend_service" "api" {
  name                  = "${var.name_prefix}-${var.shard_name}-api-backend"
  protocol              = "HTTP"
  port_name             = "http"
  timeout_sec           = 30
  load_balancing_scheme = "EXTERNAL_MANAGED"

  backend {
    group           = google_compute_instance_group.api.id
    balancing_mode  = "UTILIZATION"
    capacity_scaler = 1.0
  }

  health_checks = [var.health_check_id]
}