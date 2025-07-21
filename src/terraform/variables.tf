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

variable "enable_ssl" {
  description = "Enable SSL/HTTPS"
  type        = bool
  default     = false
}

variable "ssl_certificate_domains" {
  description = "Domains for SSL certificate"
  type        = list(string)
  default     = []
}

variable "notification_channel_ids" {
  description = "List of notification channel IDs for alerts"
  type        = list(string)
  default     = []
}

variable "bigquery_dataset_id" {
  description = "BigQuery dataset ID for log export"
  type        = string
  default     = "envoy_logs"
}

variable "use_global_deployment" {
  description = "Deploy Envoy globally across multiple regions"
  type        = bool
  default     = false
}

variable "use_optimized_image" {
  description = "Use pre-built optimized VM image with Docker pre-installed for WASM plugin"
  type        = bool
  default     = true
}
