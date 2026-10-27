data "aws_iam_policy_document" "vpc_cni_assume_role" {
  statement {
    actions = ["sts:AssumeRole", "sts:TagSession"]

    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "vpc_cni" {
  name               = "${local.cluster_name}-vpc-cni"
  assume_role_policy = data.aws_iam_policy_document.vpc_cni_assume_role.json
}

resource "aws_iam_role_policy_attachment" "vpc_cni" {
  role       = aws_iam_role.vpc_cni.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "21.29.0"

  name               = local.cluster_name
  kubernetes_version = "1.37"
  vpc_id             = module.vpc.vpc_id
  subnet_ids         = module.vpc.private_subnets

  endpoint_private_access      = true
  endpoint_public_access       = true
  endpoint_public_access_cidrs = var.operator_cidrs

  enable_cluster_creator_admin_permissions = true
  create_kms_key                           = false
  encryption_config                        = null
  enabled_log_types                        = ["api", "audit", "authenticator"]
  cloudwatch_log_group_retention_in_days   = 1

  security_group_tags = {
    "karpenter.sh/discovery" = local.cluster_name
  }
  node_security_group_tags = {
    "karpenter.sh/discovery" = local.cluster_name
  }

  eks_managed_node_groups = {
    system = {
      name                           = "${local.cluster_name}-system"
      iam_role_name                  = "${local.cluster_name}-system"
      ami_type                       = "AL2023_ARM_64_STANDARD"
      ami_release_version            = "1.37.1-20261023"
      use_latest_ami_release_version = false
      capacity_type                  = "ON_DEMAND"
      instance_types                 = ["t4g.medium"]
      min_size                       = 2
      max_size                       = 2
      desired_size                   = 2
      subnet_ids                     = module.vpc.private_subnets
      iam_role_attach_cni_policy     = false
      labels = {
        workload = "system"
      }

      taints = {
        critical_addons = {
          key    = "CriticalAddonsOnly"
          value  = "true"
          effect = "NO_SCHEDULE"
        }
      }
    }
  }

  addons = {
    vpc-cni = {
      addon_version               = "v1.23.2-eksbuild.8"
      before_compute              = true
      most_recent                 = false
      resolve_conflicts_on_create = "OVERWRITE"
      pod_identity_association = [{
        role_arn        = aws_iam_role.vpc_cni.arn
        service_account = "aws-node"
      }]
    }
    kube-proxy = {
      addon_version = "v1.37.0-eksbuild.32"
      most_recent   = false
    }
    coredns = {
      addon_version = "v1.14.7-eksbuild.22"
      most_recent   = false
    }
    eks-pod-identity-agent = {
      addon_version  = "v1.4.0-eksbuild.4"
      most_recent    = false
      before_compute = true
    }
  }
}