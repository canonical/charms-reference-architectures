# Copyright 2026 Canonical Ltd.
# See LICENSE file for licensing details.

# workaround to allow opensearch traffic across juju models
# puts all opensearch machines in extra security group that
# allows ingress on ports 9200 and 9300
locals {
  opensearch_units = merge(
    { main = { model = var.opensearch_model, units = var.main.units } },
    var.failover == null ? {} : { failover = { model = coalesce(var.failover.model, var.opensearch_model), units = var.failover.units } },
    { for app in var.apps : app.app_name => { model = coalesce(app.model, var.opensearch_model), units = app.units } },
  )

  cross_model = length(distinct([for app in values(local.opensearch_units) : app.model])) > 1

  opensearch_machines = local.cross_model ? {
    for unit in flatten([
      for app, settings in local.opensearch_units : [for index in range(settings.units) : { app = app, index = index }]
    ]) : "${unit.app}/${unit.index}" => unit
  } : {}
}

resource "terraform_data" "opensearch_units" {
  for_each = local.cross_model ? local.opensearch_units : {}
  input    = "${each.value.model}/${each.value.units}"

  depends_on = [module.opensearch]
}

data "juju_application" "opensearch" {
  for_each   = local.cross_model ? local.opensearch_units : {}
  model_uuid = juju_model.opensearch[each.value.model].uuid
  name       = each.key

  depends_on = [terraform_data.opensearch_units]

  lifecycle {
    postcondition {
      condition     = length(self.machines) == local.opensearch_units[each.key].units
      error_message = "OpenSearch app ${each.key} doesn't have all its machines yet. Apply again in a few minutes."
    }
  }
}

data "juju_machine" "opensearch" {
  for_each              = local.opensearch_machines
  model_uuid            = data.juju_application.opensearch[each.value.app].model_uuid
  machine_id            = sort(tolist(data.juju_application.opensearch[each.value.app].machines))[each.value.index]
  wait_for_ip_addresses = ["private"]
}

data "aws_instance" "opensearch" {
  for_each    = local.opensearch_machines
  instance_id = data.juju_machine.opensearch[each.key].instance_id
}

resource "aws_security_group" "opensearch" {
  count  = local.cross_model ? 1 : 0
  name   = "${var.opensearch_model}-cross-model"
  vpc_id = var.vpc_id
}

resource "aws_vpc_security_group_ingress_rule" "opensearch" {
  for_each                     = local.cross_model ? toset(["9200", "9300"]) : toset([])
  security_group_id            = aws_security_group.opensearch[0].id
  referenced_security_group_id = aws_security_group.opensearch[0].id
  ip_protocol                  = "tcp"
  from_port                    = tonumber(each.key)
  to_port                      = tonumber(each.key)
}

resource "aws_network_interface_sg_attachment" "opensearch" {
  for_each             = local.opensearch_machines
  security_group_id    = aws_security_group.opensearch[0].id
  network_interface_id = data.aws_instance.opensearch[each.key].network_interface_id
}
