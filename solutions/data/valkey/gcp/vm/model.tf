# Copyright 2026 Canonical Ltd.
# See LICENSE file for licensing details.

# Juju places machines in any subnet. With data_space, spaces=alpha keeps every machine without its
# own spaces constraint out of the data subnets.
resource "juju_model" "valkey" {
  name        = var.valkey_model
  credential  = var.machine_credential
  constraints = var.data_space == null ? null : "spaces=alpha"

  dynamic "cloud" {
    for_each = var.machine_cloud == null ? [] : [var.machine_cloud]
    content {
      name = cloud.value
    }
  }
}

# The product module created the model before data_space existed. This keeps that model.
moved {
  from = module.valkey.juju_model.this[0]
  to   = juju_model.valkey
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

  depends_on = [juju_subnet.data]
}
