# Copyright 2026 Canonical Ltd.
# See LICENSE file for licensing details.

# Juju places machines in any subnet of the VNet, and each subnet can leave through its own NAT
# gateway. The excluded subnets move to a separate space in the Valkey model, and the model
# constraint spaces=alpha keeps every machine in the rest.
resource "juju_model" "valkey" {
  name        = var.valkey_model
  credential  = var.machine_credential
  constraints = length(var.excluded_subnets) == 0 ? null : "spaces=alpha"

  dynamic "cloud" {
    for_each = var.machine_cloud == null ? [] : [var.machine_cloud]
    content {
      name = cloud.value
    }
  }
}

resource "juju_space" "excluded" {
  count      = length(var.excluded_subnets) == 0 ? 0 : 1
  model_uuid = juju_model.valkey.uuid
  name       = "excluded"
}

resource "juju_subnet" "excluded" {
  for_each   = toset(var.excluded_subnets)
  model_uuid = juju_model.valkey.uuid
  cidr       = each.value
  space_name = juju_space.excluded[0].name
}

# Hands the model on only once the subnets have moved, so no machine starts in an excluded subnet.
# The product module has its own provider block, so it cannot take depends_on.
resource "terraform_data" "valkey_model" {
  input = {
    name = juju_model.valkey.name
    uuid = juju_model.valkey.uuid
  }

  depends_on = [juju_subnet.excluded]
}
