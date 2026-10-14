# Copyright 2026 Canonical Ltd.
# See LICENSE file for licensing details.

locals {
  eks_cluster = one(data.aws_eks_cluster.this[*])
  lb_subnets  = var.load_balancer == null ? [] : var.load_balancer.subnet_ids
  valkey_app  = module.valkey.credentials.valkey.app_name
}

data "aws_eks_cluster" "this" {
  count = var.load_balancer == null ? 0 : 1
  name  = var.load_balancer.eks_cluster
}

ephemeral "aws_eks_cluster_auth" "this" {
  count = var.load_balancer == null ? 0 : 1
  name  = var.load_balancer.eks_cluster
}

# One static IP per subnet, reserved before Valkey so the server certificate can cover them.
resource "aws_eip" "valkey" {
  count  = length(local.lb_subnets)
  domain = "vpc"

  tags = {
    Name = "${var.valkey_model}-valkey-external-${count.index}"
  }
}

# Follows the primary: the charm moves the role=primary pod label on failover. The annotations
# target the NLB support built into EKS, which needs no AWS Load Balancer Controller.
resource "kubernetes_service_v1" "valkey_external" {
  count = var.load_balancer == null ? 0 : 1

  metadata {
    name      = "${local.valkey_app}-external"
    namespace = var.valkey_model # Juju names the namespace after the model.

    annotations = {
      "service.beta.kubernetes.io/aws-load-balancer-type"            = "nlb"
      "service.beta.kubernetes.io/aws-load-balancer-subnets"         = join(",", local.lb_subnets)
      "service.beta.kubernetes.io/aws-load-balancer-eip-allocations" = join(",", aws_eip.valkey[*].allocation_id)
    }
  }

  spec {
    type                        = "LoadBalancer"
    load_balancer_source_ranges = var.load_balancer.allowed_cidrs

    selector = {
      application-name = local.valkey_app
      role             = "primary"
    }

    port {
      name        = "valkey-tls"
      port        = module.valkey.credentials.valkey.tls_port
      target_port = module.valkey.credentials.valkey.tls_port
    }
  }
}
