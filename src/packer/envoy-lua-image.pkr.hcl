packer {
  required_plugins {
    googlecompute = {
      version = ">= 1.0.0"
      source  = "github.com/hashicorp/googlecompute"
    }
  }
}

variable "project_id" {
  type = string
}

variable "zone" {
  type    = string
  default = "us-east1-b"
}

source "googlecompute" "envoy-lua-base" {
  project_id          = var.project_id
  source_image_family = "ubuntu-2204-lts"
  zone                = var.zone
  image_name          = "envoy-lua-optimized-{{timestamp}}"
  image_family        = "envoy-lua-optimized"
  machine_type        = "e2-standard-2"
  disk_size           = 20
  ssh_username        = "ubuntu"
  
  # Use IAP for SSH tunneling
  use_iap             = true

  metadata = {
    enable-oslogin = "FALSE"
    block-project-ssh-keys = "FALSE"
  }
}

build {
  sources = ["source.googlecompute.envoy-lua-base"]

  # Install Docker and required tools
  provisioner "shell" {
    inline = [
      "sudo apt-get update",
      "sudo apt-get install -y docker.io docker-compose curl jq",
      "sudo systemctl enable docker",
      "sudo systemctl start docker"
    ]
  }

  # Install Rust for building the tenant lookup service
  provisioner "shell" {
    inline = [
      "curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y",
      ". $HOME/.cargo/env"
    ]
  }

  # Copy tenant lookup service source code
  provisioner "file" {
    source      = "../tenant-lookup-service"
    destination = "/tmp/tenant-lookup-service"
  }

  provisioner "file" {
    source      = "../tenant-routing-core"
    destination = "/tmp/tenant-routing-core"
  }

  # Build tenant lookup service
  provisioner "shell" {
    inline = [
      "cd /tmp/tenant-lookup-service",
      "$HOME/.cargo/bin/cargo build --release",
      "sudo mkdir -p /opt/tenant-lookup",
      "sudo cp target/release/tenant-lookup-service /opt/tenant-lookup/",
      "sudo chmod 755 /opt/tenant-lookup/tenant-lookup-service"
    ]
  }

  # Create Docker image for tenant lookup service
  provisioner "shell" {
    inline = [
      "cd /tmp/tenant-lookup-service",
      "sudo docker build -t tenant-lookup:latest .",
      "sudo docker tag tenant-lookup:latest gcr.io/${var.project_id}/tenant-lookup:latest"
    ]
  }

  # Configure Docker to authenticate with GCR
  provisioner "shell" {
    inline = [
      "sudo gcloud auth configure-docker gcr.io --quiet"
    ]
  }

  # Pre-pull Docker images
  provisioner "shell" {
    inline = [
      "echo 'Pre-pulling Docker images...'",
      "sudo docker pull envoyproxy/envoy:v1.28-latest",
      "sudo docker pull gcr.io/${var.project_id}/gcs-proxy:latest || echo 'GCS proxy image will be pulled at runtime'"
    ]
  }

  # Create systemd service for tenant lookup
  provisioner "shell" {
    inline = [
      "sudo tee /etc/systemd/system/tenant-lookup.service > /dev/null <<EOF",
      "[Unit]",
      "Description=Tenant Lookup Service",
      "After=docker.service",
      "Requires=docker.service",
      "",
      "[Service]",
      "Type=simple",
      "Restart=always",
      "RestartSec=5",
      "ExecStartPre=-/usr/bin/docker stop tenant-lookup",
      "ExecStartPre=-/usr/bin/docker rm tenant-lookup",
      "ExecStart=/usr/bin/docker run --name tenant-lookup -p 8080:8080 --rm gcr.io/${var.project_id}/tenant-lookup:latest",
      "",
      "[Install]",
      "WantedBy=multi-user.target",
      "EOF",
      "sudo systemctl daemon-reload"
    ]
  }

  # Clean up build artifacts
  provisioner "shell" {
    inline = [
      "rm -rf /tmp/tenant-lookup-service /tmp/tenant-routing-core",
      "sudo apt-get autoremove -y",
      "sudo apt-get clean",
      "sudo rm -rf /var/lib/apt/lists/*",
      "rm -rf ~/.cargo ~/.rustup"
    ]
  }
}