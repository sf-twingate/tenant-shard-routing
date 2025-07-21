variable "name_prefix" {
  description = "Prefix for all resource names"
  type        = string
}

variable "project_id" {
  description = "Google Cloud project ID"
  type        = string
}

variable "regions" {
  description = "Map of regions to deploy Envoy instances"
  type = map(object({
    region          = string
    zones           = list(string)
    instance_count  = number
    machine_type    = string
  }))
  default = {
    us = {
      region         = "us-central1"
      zones          = ["us-central1-a", "us-central1-b", "us-central1-c"]
      instance_count = 3
      machine_type   = "e2-medium"
    }
    europe = {
      region         = "europe-west1"
      zones          = ["europe-west1-b", "europe-west1-c", "europe-west1-d"]
      instance_count = 3
      machine_type   = "e2-medium"
    }
    asia = {
      region         = "asia-southeast1"
      zones          = ["asia-southeast1-a", "asia-southeast1-b", "asia-southeast1-c"]
      instance_count = 3
      machine_type   = "e2-medium"
    }
  }
}

variable "min_instances_per_region" {
  description = "Minimum number of instances per region"
  type        = number
  default     = 2
}

variable "max_instances_per_region" {
  description = "Maximum number of instances per region"
  type        = number
  default     = 10
}

variable "network" {
  description = "VPC network name"
  type        = string
}

variable "subnetwork_prefix" {
  description = "Prefix for subnetwork names (will append region)"
  type        = string
}

variable "service_account_email" {
  description = "Service account email for Envoy instances"
  type        = string
}

variable "shard_names" {
  description = "List of shard names"
  type        = list(string)
}

variable "shard_backends" {
  description = "Map of shard modules with their outputs"
  type        = any
}

variable "gcs_bucket_name" {
  description = "GCS bucket name for tenant mapping"
  type        = string
}

variable "use_lua_filter" {
  description = "Use Lua filter instead of WASM"
  type        = bool
  default     = false
}

variable "wasm_filter_path" {
  description = "Path to WASM filter source code"
  type        = string
  default     = ""
}

variable "enable_cdn" {
  description = "Enable Cloud CDN for static content"
  type        = bool
  default     = true
}

variable "enable_cloud_armor" {
  description = "Enable Cloud Armor for DDoS protection"
  type        = bool
  default     = true
}
variable "use_optimized_image" {
  description = "Use pre-built optimized VM image with Docker pre-installed"
  type        = bool
  default     = false
}
