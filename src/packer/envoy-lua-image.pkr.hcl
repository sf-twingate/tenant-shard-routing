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
  image_name          = "envoy-lua-{{timestamp}}"
  image_family        = "envoy-lua"
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
      "sudo apt-get install -y docker.io docker-compose curl jq build-essential pkg-config libssl-dev",
      "sudo systemctl enable docker",
      "sudo systemctl start docker"
    ]
  }

  # Copy tenant lookup service source code for Docker build
  provisioner "file" {
    source      = "../tenant-lookup-service"
    destination = "/tmp/tenant-lookup-service"
  }

  provisioner "file" {
    source      = "../tenant-routing-core"
    destination = "/tmp/tenant-routing-core"
  }

  # Create Docker image for tenant lookup service
  provisioner "shell" {
    inline = [
      "cd /tmp",
      "sudo docker build -t tenant-lookup-service:latest -f tenant-lookup-service/Dockerfile .",
      "sudo docker tag tenant-lookup-service:latest gcr.io/${var.project_id}/tenant-lookup-service:latest"
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
      "sudo docker pull envoyproxy/envoy:v1.28-latest"
    ]
  }

  # Clean up build artifacts
  provisioner "shell" {
    inline = [
      "rm -rf /tmp/tenant-lookup-service /tmp/tenant-routing-core",
      "sudo apt-get autoremove -y",
      "sudo apt-get clean",
      "sudo rm -rf /var/lib/apt/lists/*"
    ]
  }
}