module "karpenter" {
  source  = "terraform-aws-modules/eks/aws//modules/karpenter"
  version = "21.26.0"

  cluster_name = module.eks.cluster_name
  region       = var.region

  create_iam_role                        = true
  create_pod_identity_association        = true
  create_node_iam_role                   = true
  create_access_entry                    = true
  create_instance_profile                = true
  enable_spot_termination                = true
  node_iam_role_attach_cni_policy        = false
  node_iam_role_source_account_condition = true

  iam_role_name                 = "${local.cluster_name}-karpenter-controller"
  iam_role_use_name_prefix      = false
  iam_policy_name               = "${local.cluster_name}-karpenter-controller"
  iam_policy_use_name_prefix    = false
  node_iam_role_name            = "${local.cluster_name}-karpenter-node"
  node_iam_role_use_name_prefix = false
  queue_name                    = local.cluster_name

  tags = {
    "karpenter.sh/discovery" = local.cluster_name
  }
}