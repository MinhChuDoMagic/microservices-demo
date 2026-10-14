data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  cluster_name = var.project
  vpc_cidr     = "10.42.0.0/16"
  azs          = slice(sort(data.aws_availability_zones.available.names), 0, 2)
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "6.7.3"

  name = "${var.project}-vpc"
  cidr = local.vpc_cidr
  azs  = local.azs

  public_subnets  = ["10.42.0.0/24", "10.42.1.0/24"]
  private_subnets = ["10.42.16.0/20", "10.42.32.0/20"]
  intra_subnets   = ["10.42.64.0/24", "10.42.65.0/24"]

  enable_nat_gateway   = false
  enable_dns_support   = true
  enable_dns_hostnames = true

  public_subnet_tags = {
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
    "kubernetes.io/role/elb"                      = "1"
  }

  private_subnet_tags = {
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
    "kubernetes.io/role/internal-elb"             = "1"
    "karpenter.sh/discovery"                      = local.cluster_name
  }
}

module "gateway_endpoints" {
  source  = "terraform-aws-modules/vpc/aws//modules/vpc-endpoints"
  version = "6.7.3"

  vpc_id = module.vpc.vpc_id

  endpoints = {
    s3 = {
      service         = "s3"
      service_type    = "Gateway"
      route_table_ids = module.vpc.private_route_table_ids
    }
    dynamodb = {
      service         = "dynamodb"
      service_type    = "Gateway"
      route_table_ids = module.vpc.private_route_table_ids
    }
  }
}

module "interface_endpoints" {
  count   = var.enable_interface_endpoints ? 1 : 0
  source  = "terraform-aws-modules/vpc/aws//modules/vpc-endpoints"
  version = "6.7.3"

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  create_security_group      = true
  security_group_name_prefix = "${var.project}-vpce-"
  security_group_description = "HTTPS from private VPC resources to interface endpoints"
  security_group_rules = {
    ingress_https = {
      description = "HTTPS from the VPC"
      cidr_blocks = [local.vpc_cidr]
    }
  }

  endpoints = {
    ecr_api = {
      service             = "ecr.api"
      private_dns_enabled = true
    }
    ecr_dkr = {
      service             = "ecr.dkr"
      private_dns_enabled = true
    }
    secretsmanager = {
      service             = "secretsmanager"
      private_dns_enabled = true
    }
    sqs = {
      service             = "sqs"
      private_dns_enabled = true
    }
    sts = {
      service             = "sts"
      private_dns_enabled = true
    }
  }
}