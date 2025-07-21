variable "name_prefix" {
  description = "Prefix for all resource names"
  type        = string
}

variable "domain" {
  description = "Domain for the service"
  type        = string
}

variable "backend_service_id" {
  description = "ID of the global backend service"
  type        = string
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