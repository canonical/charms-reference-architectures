# Copyright 2026 Canonical Ltd.
# See LICENSE file for licensing details.

locals {
  private_cidrs = [for s in data.aws_subnet.private : s.cidr_block]
}

# Juju ignores a machine's spaces for placement when its only space is alpha, unless a constraint
# names alpha. So with external_access, spaces=alpha keeps every machine in alpha's subnets.
resource "juju_model" "valkey" {
  name        = var.valkey_model
  credential  = var.machine_credential
  constraints = var.external_access == null ? null : "spaces=alpha"

  dynamic "cloud" {
    for_each = var.machine_cloud == null ? [] : [var.machine_cloud]
    content {
      name = cloud.value
    }
  }
}

# Every subnet starts in alpha. With external_access, the VPC's private subnets move to a space
# nothing uses, so alpha holds only public subnets and every machine gets a public IP.
data "aws_subnets" "private" {
  count = var.external_access == null ? 0 : 1

  filter {
    name   = "vpc-id"
    values = [var.external_access.vpc_id]
  }

  filter {
    name   = "map-public-ip-on-launch"
    values = ["false"]
  }
}

data "aws_subnet" "private" {
  for_each = toset(flatten(data.aws_subnets.private[*].ids))
  id       = each.value
}

resource "juju_space" "private" {
  count      = var.external_access == null ? 0 : 1
  model_uuid = juju_model.valkey.uuid
  name       = "private"
}

resource "juju_subnet" "private" {
  for_each   = toset(local.private_cidrs)
  model_uuid = juju_model.valkey.uuid
  cidr       = each.value
  space_name = juju_space.private[0].name
}

# Hands the model on only once the subnets have moved, so no machine starts in a private subnet.
# The product module has its own provider block, so it cannot take depends_on.
resource "terraform_data" "valkey_model" {
  input = {
    name = juju_model.valkey.name
    uuid = juju_model.valkey.uuid
  }

  depends_on = [juju_subnet.private]
}
