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

variable "alert_email" {
  description = "Email address for cost alerts; provide in the gitignored terraform.tfvars."
  type        = string
}

variable "github_owner" {
  description = "GitHub owner for the OIDC trust policy."
  type        = string
}

variable "github_repo" {
  description = "GitHub repository for the OIDC trust policy."
  type        = string
}

variable "github_owner_id" {
  description = "Numeric GitHub owner ID for immutable OIDC subjects; null for legacy repositories."
  type        = string
  default     = null
}

variable "github_repo_id" {
  description = "Numeric GitHub repository ID for immutable OIDC subjects; null for legacy repositories."
  type        = string
  default     = null
}