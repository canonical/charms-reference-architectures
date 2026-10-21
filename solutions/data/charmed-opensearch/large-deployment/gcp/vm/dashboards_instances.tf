# Copyright 2026 Canonical Ltd.
# See LICENSE file for licensing details.

data "google_compute_zones" "available" {}

# Juju's provider doesn't report machine zones, so ask the juju CLI (logged into the same controller).
data "external" "dashboards_instances" {
  count   = local.lb == null ? 0 : 1
  program = ["bash", "${path.module}/scripts/dashboards_instances.sh"]

  query = {
    model    = juju_model.opensearch[var.opensearch_model].uuid
    machines = join(",", sort(local.dashboards_app.machines))
  }

  lifecycle {
    postcondition {
      condition = alltrue([
        for value in values(self.result) : contains(local.zones, value)
      ])
      error_message = "An OpenSearch Dashboards machine is outside the selected region."
    }
  }
}

# Select the internal address on the configured network.
data "google_compute_instance" "dashboards" {
  count = local.lb == null ? 0 : var.opensearch_dashboards.units
  name  = local.dashboards_instance_names[count.index]
  zone  = local.dashboards_machine_zones[local.dashboards_instance_names[count.index]]

  lifecycle {
    postcondition {
      condition     = anytrue([for nic in self.network_interface : nic.subnetwork == data.google_compute_subnetwork.dashboards[0].self_link])
      error_message = "An OpenSearch Dashboards machine is outside the selected backend subnet."
    }
  }
}
