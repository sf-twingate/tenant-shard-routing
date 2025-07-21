variable "name_prefix" {
  description = "Prefix for all resource names"
  type        = string
}

variable "domain" {
  description = "Domain for the service"
  type        = string
}

variable "envoy_instance_group_id" {
  description = "ID of the Envoy instance group"
  type        = string
}

variable "health_check_id" {
  description = "ID of the health check resource"
  type        = string
}

variable "network" {
  description = "VPC network name"
  type        = string
  default     = "default"
}

variable "enable_ssl" {
  description = "Enable SSL/HTTPS"
  type        = bool
  default     = false
}

variable "ssl_domains" {
  description = "Domains for SSL certificate"
  type        = list(string)
  default     = []
}