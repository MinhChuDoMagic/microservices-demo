variable "region" {
  description = "AWS region. Single-region project (D-02)."
  type        = string
  default     = "us-east-1"
}

variable "project" {
  description = "Value of the Project tag, consumed by the teardown sweep (D-07)."
  type        = string
  default     = "microservices-demo"
}

variable "environment" {
  description = "Value of the Environment cost-allocation tag."
  type        = string
  default     = "practice"
}

variable "operator_cidr" {
  description = "Trusted public IPv4 CIDR allowed to reach the EKS API endpoint."
  type        = string

  validation {
    condition     = can(cidrnetmask(var.operator_cidr)) && var.operator_cidr != "0.0.0.0/0"
    error_message = "operator_cidr must be a valid IPv4 CIDR other than 0.0.0.0/0."
  }
}

variable "enable_interface_endpoints" {
  description = "Create optional billed interface VPC endpoints for deliberate comparison sessions."
  type        = bool
  default     = false
}