# Copyright 2025 Canonical Ltd.
# See LICENSE file for licensing details.

## ====================================================
## Kubernetes infra (EKS)
## ====================================================

resource "aws_eks_cluster" "eks" {
  count   = var.EKS_CLUSTER_NAME != "" ? 1 : 0
  name    = var.EKS_CLUSTER_NAME

  access_config {
    authentication_mode = "API"
  }

  role_arn = aws_iam_role.cluster[count.index].arn
  version  = "1.32"

  vpc_config {
    subnet_ids = [
      aws_subnet.deployments_subnet.id,
      aws_subnet.controller_subnet.id,
    ]
  }

  depends_on = [
    aws_iam_role_policy_attachment.cluster_AmazonEKSClusterPolicy,
  ]
}

resource "aws_iam_role" "cluster" {
  count   = var.EKS_CLUSTER_NAME != "" ? 1 : 0
  name    = "eks-cluster"
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