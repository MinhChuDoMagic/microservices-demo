output "cluster_name" {
  description = "Name of the L1 EKS cluster."
  value       = module.eks.cluster_name
}

output "system_node_group_name" {
  description = "Name of the required on-demand system node group."
  value       = module.eks.eks_managed_node_groups["system"].node_group_name
}