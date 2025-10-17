# Copyright 2025 Canonical Ltd.
# See LICENSE file for licensing details.

output "infrastructure" {
  value = {
    vpc_id                = aws_vpc.main_vpc.id
    controller_subnet_id  = aws_subnet.controller_subnet.id
    deployments_subnet_id = aws_subnet.deployments_subnet.id
    bastion_public_ip     = var.PROVISION_BASTION ? aws_instance.bastion_host[0].public_ip : null
  }
}

output "eks_cluster" {
  value = var.EKS_CLUSTER_NAME != "" ? {
    name                   = aws_eks_cluster.eks[0].name
    cluster_endpoint       = aws_eks_cluster.eks[0].endpoint
    certificate_authority  = aws_eks_cluster.eks[0].certificate_authority
  } : null
  sensitive = true
}