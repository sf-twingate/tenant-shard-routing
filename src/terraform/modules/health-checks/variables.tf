variable "name_prefix" {
  description = "Prefix for all resource names"
  type        = string
}

variable "health_check_interval" {
  description = "How often to check health in seconds"
  type        = number
  default     = 5
}

variable "health_check_timeout" {
  description = "Timeout for health check in seconds"
  type        = number
  default     = 5
}

variable "health_check_path" {
  description = "Path for HTTP health check"
  type        = string
  default     = "/health"
}

variable "health_check_port" {
  description = "Port for HTTP health check"
  type        = number
  default     = 80
}

variable "network" {
  description = "VPC network name"
  type        = string
  default     = "default"
}