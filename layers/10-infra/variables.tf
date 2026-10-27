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

variable "operator_cidrs" {
  description = "Trusted public IPv4 CIDRs allowed to reach the EKS API endpoint."
  type        = list(string)

  validation {
    condition = (
      length(var.operator_cidrs) > 0 &&
      length(distinct(var.operator_cidrs)) == length(var.operator_cidrs) &&
      alltrue([for cidr in var.operator_cidrs : can(cidrnetmask(cidr)) && cidr != "0.0.0.0/0"])
    )
    error_message = "operator_cidrs must be a non-empty list of unique IPv4 CIDRs other than 0.0.0.0/0."
  }
}

variable "enable_interface_endpoints" {
  description = "Create optional billed interface VPC endpoints for deliberate comparison sessions."
  type        = bool
  default     = false
}