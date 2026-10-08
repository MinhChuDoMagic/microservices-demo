terraform {
  required_version = "= 1.16.4"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "= 6.66.0"
    }
  }

}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project     = var.project
      Layer       = "00-bootstrap"
      ManagedBy   = "terraform"
      Environment = var.environment
    }
  }
}