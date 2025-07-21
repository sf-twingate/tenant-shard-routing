variable "shard_name" {
  description = "Name of the shard"
  type        = string
}

variable "name_prefix" {
  description = "Prefix for all resource names"
  type        = string
}

variable "region" {
  description = "GCP Region"
  type        = string
}

variable "zone" {
  description = "GCP Zone"
  type        = string
}

variable "network" {
  description = "VPC network"
  type        = string
  default     = "default"
}

variable "subnetwork" {
  description = "VPC subnetwork"
  type        = string
  default     = "default"
}

# Services are defined within the module as they're standard across all shards

variable "health_check_id" {
  description = "Health check ID to use for backend services"
  type        = string
}