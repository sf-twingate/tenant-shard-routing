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

source "googlecompute" "envoy-wasm-base" {
  project_id          = var.project_id
  source_image_family = "ubuntu-2204-lts"
  zone                = var.zone
  image_name          = "envoy-wasm-{{timestamp}}"
  image_family        = "envoy-wasm"
  machine_type        = "e2-standard-2"  # Need more power for building
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
  sources = ["source.googlecompute.envoy-wasm-base"]

  # Install Docker and build tools
  provisioner "shell" {
    inline = [
      "sudo apt-get update",
      "sudo apt-get install -y docker.io docker-compose curl jq build-essential",
      "sudo systemctl enable docker",
      "sudo systemctl start docker"
    ]
  }

  # Install Rust for WASM building
  provisioner "shell" {
    inline = [
      "curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y",
      ". $HOME/.cargo/env",
      "$HOME/.cargo/bin/rustup target add wasm32-wasip1"
    ]
  }

  # Copy WASM filter source code
  provisioner "file" {
    source      = "../wasm-filter"
    destination = "/tmp/wasm-filter"
  }

  provisioner "file" {
    source      = "../tenant-routing-core"
    destination = "/tmp/tenant-routing-core"
  }

  # Build WASM filter
  provisioner "shell" {
    inline = [
      "cd /tmp/wasm-filter",
      "$HOME/.cargo/bin/cargo build --target wasm32-wasip1 --release",
      "sudo mkdir -p /opt/envoy",
      "sudo cp target/wasm32-wasip1/release/tenant_router.wasm /opt/envoy/tenant-router.wasm",
      "sudo chmod 644 /opt/envoy/tenant-router.wasm"
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

  # Clean up build artifacts
  provisioner "shell" {
    inline = [
      "rm -rf /tmp/wasm-filter /tmp/tenant-routing-core",
      "sudo apt-get remove -y build-essential",
      "sudo apt-get autoremove -y",
      "sudo apt-get clean",
      "sudo rm -rf /var/lib/apt/lists/*",
      "rm -rf ~/.cargo ~/.rustup"
    ]
  }
}