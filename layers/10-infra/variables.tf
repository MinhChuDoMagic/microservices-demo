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