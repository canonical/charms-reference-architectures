# Copyright 2025 Canonical Ltd.
# See LICENSE file for licensing details.

## ====================================================
## Kubernetes infra (EKS)
## ====================================================

resource "aws_eks_cluster" "eks" {
  count = var.EKS_CLUSTER_NAME != "" ? 1 : 0
  name  = var.EKS_CLUSTER_NAME

  access_config {
    authentication_mode                         = "API"
    bootstrap_cluster_creator_admin_permissions = true
  }

  role_arn = aws_iam_role.cluster[count.index].arn
  version  = "1.35"

  vpc_config {
    subnet_ids = [
      aws_subnet.deployments_peers_subnet.id,
      aws_subnet.deployments_clients_subnet.id,
      aws_subnet.controller_subnet.id,
    ]
  }

  depends_on = [
    aws_iam_role_policy_attachment.cluster_AmazonEKSClusterPolicy,
  ]
}

resource "aws_iam_role" "cluster" {
  count = var.EKS_CLUSTER_NAME != "" ? 1 : 0
  name  = "eks-cluster"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "sts:AssumeRole",
          "sts:TagSession"
        ]
        Effect = "Allow"
        Principal = {
          Service = "eks.amazonaws.com"
        }
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "cluster_AmazonEKSClusterPolicy" {
  count      = var.EKS_CLUSTER_NAME != "" ? 1 : 0
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.cluster[count.index].name
}

resource "aws_iam_role" "eks_nodes" {
  count = var.EKS_CLUSTER_NAME != "" ? 1 : 0
  name  = "${var.EKS_CLUSTER_NAME}-nodes"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "nodes_AmazonEKSWorkerNodePolicy" {
  count      = var.EKS_CLUSTER_NAME != "" ? 1 : 0
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.eks_nodes[count.index].name
}

resource "aws_iam_role_policy_attachment" "nodes_AmazonEKS_CNI_Policy" {
  count      = var.EKS_CLUSTER_NAME != "" ? 1 : 0
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.eks_nodes[count.index].name
}

resource "aws_iam_role_policy_attachment" "nodes_AmazonEC2ContainerRegistryPullOnly" {
  count      = var.EKS_CLUSTER_NAME != "" ? 1 : 0
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPullOnly"
  role       = aws_iam_role.eks_nodes[count.index].name
}

resource "aws_eks_node_group" "workers" {
  count = var.EKS_CLUSTER_NAME != "" ? 1 : 0

  cluster_name    = aws_eks_cluster.eks[count.index].name
  node_group_name = "${var.EKS_CLUSTER_NAME}-workers"
  node_role_arn   = aws_iam_role.eks_nodes[count.index].arn
  subnet_ids = [
    aws_subnet.controller_subnet.id,
    aws_subnet.deployments_peers_subnet.id,
    aws_subnet.deployments_clients_subnet.id,
  ]

  instance_types = var.EKS_NODE_INSTANCE_TYPES

  scaling_config {
    desired_size = 3
    min_size     = 1
    max_size     = 5
  }

  update_config {
    max_unavailable = 1
  }

  depends_on = [
    aws_iam_role_policy_attachment.nodes_AmazonEKSWorkerNodePolicy,
    aws_iam_role_policy_attachment.nodes_AmazonEKS_CNI_Policy,
    aws_iam_role_policy_attachment.nodes_AmazonEC2ContainerRegistryPullOnly,
    aws_route_table_association.controller_private_assoc,
    aws_route_table_association.deployment_peers_private_assoc,
    aws_route_table_association.deployment_clients_private_assoc,
  ]
}

resource "aws_iam_role" "ebs_csi" {
  count = var.EKS_CLUSTER_NAME != "" ? 1 : 0
  name  = "${var.EKS_CLUSTER_NAME}-ebs-csi"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowEksAuthToAssumeRoleForPodIdentity"
        Effect = "Allow"
        Principal = {
          Service = "pods.eks.amazonaws.com"
        }
        Action = [
          "sts:AssumeRole",
          "sts:TagSession",
        ]
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ebs_csi_AmazonEBSCSIDriverPolicy" {
  count      = var.EKS_CLUSTER_NAME != "" ? 1 : 0
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
  role       = aws_iam_role.ebs_csi[count.index].name
}

resource "aws_eks_addon" "pod_identity_agent" {
  count        = var.EKS_CLUSTER_NAME != "" ? 1 : 0
  cluster_name = aws_eks_cluster.eks[count.index].name
  addon_name   = "eks-pod-identity-agent"

  depends_on = [aws_eks_node_group.workers]
}

resource "aws_eks_pod_identity_association" "ebs_csi" {
  count           = var.EKS_CLUSTER_NAME != "" ? 1 : 0
  cluster_name    = aws_eks_cluster.eks[count.index].name
  namespace       = "kube-system"
  service_account = "ebs-csi-controller-sa"
  role_arn        = aws_iam_role.ebs_csi[count.index].arn

  depends_on = [
    aws_eks_addon.pod_identity_agent,
    aws_iam_role_policy_attachment.ebs_csi_AmazonEBSCSIDriverPolicy,
  ]
}

resource "aws_eks_addon" "ebs_csi" {
  count        = var.EKS_CLUSTER_NAME != "" ? 1 : 0
  cluster_name = aws_eks_cluster.eks[count.index].name
  addon_name   = "aws-ebs-csi-driver"

  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "PRESERVE"

  depends_on = [aws_eks_pod_identity_association.ebs_csi]
}
