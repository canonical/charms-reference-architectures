# Copyright 2026 Canonical Ltd.
# See LICENSE file for licensing details.

# Juju places machines in any subnet of the VNet, each with its own NAT gateway. spaces=alpha keeps
# every machine without its own spaces constraint out of the excluded and data subnets.
resource "juju_model" "valkey" {
  name        = var.valkey_model
  credential  = var.machine_credential
  constraints = length(var.excluded_subnets) == 0 && var.data_space == null ? null : "spaces=alpha"

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
}

# Hands on the model once the subnets have moved. The product module can't take depends_on.
# Callers read .input, so adding this resource to a running deployment doesn't replace Valkey.
resource "terraform_data" "valkey_model" {
  input = {
    name = juju_model.valkey.name
    uuid = juju_model.valkey.uuid
  }

  depends_on = [juju_subnet.data, juju_subnet.excluded]
}
