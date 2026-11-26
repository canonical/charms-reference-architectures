# Copyright 2026 Canonical Ltd.
# See LICENSE file for licensing details.

locals {
  private_cidrs = [for s in data.aws_subnet.private : s.cidr_block]
}

# Juju ignores a machine's spaces for placement when its only space is alpha, unless a constraint
# names alpha. So spaces=alpha keeps every machine without its own spaces constraint in alpha.
resource "juju_model" "valkey" {
  name        = var.valkey_model
  credential  = var.machine_credential
  constraints = var.external_access == null && var.data_space == null ? null : "spaces=alpha"

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

# Valkey binds every endpoint to this space, and its machines start in these subnets.
resource "juju_space" "data" {
  count      = var.data_space == null ? 0 : 1
  model_uuid = juju_model.valkey.uuid
  name       = "data"
}

resource "juju_subnet" "data" {
  for_each   = toset(var.data_space == null ? [] : var.data_space.cidrs)
  model_uuid = juju_model.valkey.uuid
  cidr       = each.value
  space_name = juju_space.data[0].name

  lifecycle {
    precondition {
      condition     = !contains(local.private_cidrs, each.value)
      error_message = "With external_access, data_space.cidrs must list public subnets only, so Valkey keeps a public IP."
    }
  }
}

# Hands on the model once the subnets have moved. The product module can't take depends_on.
# Callers read .input, so adding this resource to a running deployment doesn't replace Valkey.
resource "terraform_data" "valkey_model" {
  input = {
    name = juju_model.valkey.name
    uuid = juju_model.valkey.uuid
  }

  depends_on = [juju_subnet.data, juju_subnet.private]
}
