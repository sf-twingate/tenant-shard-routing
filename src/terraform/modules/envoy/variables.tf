variable "name_prefix" {
  description = "Prefix for all resource names"
  type        = string
}

variable "zone" {
  description = "GCP Zone"
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
  description = "GCS bucket containing tenant mappings"
  type        = string
}

variable "service_account_email" {
  description = "Service account email for GCS access"
  type        = string
}

variable "machine_type" {
  description = "Machine type for Envoy instance"
  type        = string
  default     = "e2-standard-2"
}

variable "network" {
  description = "VPC network name"
  type        = string
  default     = "default"
}

variable "subnetwork" {
  description = "VPC subnetwork name"
  type        = string
  default     = null
}

variable "wasm_filter_path" {
  description = "Path to WASM filter source directory"
  type        = string
}

variable "use_lua_filter" {
  description = "Use Lua filter with Rust service instead of WASM filter"
  type        = bool
  default     = false
}

variable "project_id" {
  description = "GCP Project ID"
  type        = string
}

variable "use_optimized_image" {
  description = "Use pre-built optimized VM image with Docker pre-installed"
  type        = bool
  default     = false
}