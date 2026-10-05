# Copyright 2026 Canonical Ltd.
# See LICENSE file for licensing details.

terraform {
  required_version = ">= 1.11"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0"
    }
    juju = {
      source  = "juju/juju"
      version = ">= 2.2.1"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.30"
    }
  }
}

# Both providers read their credentials from the environment: the juju CLI or JUJU_* variables,
# and the AWS CLI profile or AWS_* variables.
provider "aws" {
  region = var.aws_region
}

provider "juju" {}

# Only used with load_balancer set: reaches the EKS cluster with a token for the aws provider's
# identity, which needs an access entry on the cluster.
provider "kubernetes" {
  host                   = local.eks_cluster == null ? null : local.eks_cluster.endpoint
  cluster_ca_certificate = local.eks_cluster == null ? null : base64decode(local.eks_cluster.certificate_authority[0].data)
  token                  = one(ephemeral.aws_eks_cluster_auth.this[*].token)
}
