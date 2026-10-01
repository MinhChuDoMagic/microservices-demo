terraform {
  required_version = "= 1.16.4"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "= 6.66.0"
    }
  }

  backend "s3" {}
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project     = var.project
      Layer       = "10-infra"
      ManagedBy   = "terraform"
      Environment = var.environment
    }
  }
}