variable "project_id" {
  description = "GCP Project ID"
  type        = string
}

variable "region" {
  description = "GCP Region for GCS bucket"
  type        = string
}

variable "name_prefix" {
  description = "Prefix for all resource names"
  type        = string
}

variable "shard_names" {
  description = "List of shard names for initial tenant mappings"
  type        = list(string)
}