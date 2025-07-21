variable "project_id" {
  description = "GCP Project ID"
  type        = string
}

variable "region" {
  description = "GCP Region"
  type        = string
  default     = "us-central1"
}

variable "zone" {
  description = "GCP Zone"
  type        = string
  default     = "us-central1-a"
}

variable "name_prefix" {
  description = "Prefix for all resource names"
  type        = string
  default     = "tenant-routing"
}

variable "domain" {
  description = "Domain for the service"
  type        = string
  default     = "example.com"
}

# Shard configuration - just specify which shards to create
variable "shard_names" {
  description = "List of shard names to create"
  type        = list(string)
  default     = ["shard1", "shard2"]
}

# Filter implementation selection
variable "use_lua_filter" {
  description = "Use Lua filter with tenant lookup service instead of WASM filter"
  type        = bool
  default     = false
}