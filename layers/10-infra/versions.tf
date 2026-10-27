terraform {
  required_version = "= 1.17.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "= 6.70.0"
    }
    cloudinit = {
      source  = "hashicorp/cloudinit"
      version = "= 2.4.1"
    }
    time = {
      source  = "hashicorp/time"
      version = "= 0.14.2"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "= 4.4.1"
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