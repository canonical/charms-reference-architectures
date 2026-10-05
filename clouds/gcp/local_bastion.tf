# Copyright 2026 Canonical Ltd.
# See LICENSE file for licensing details.

## ====================================================
## Set up Host Machine for Juju Controller (Optional)
## ====================================================

# write a bash script to initialize the controller
resource "local_file" "host_set_up_script" {
  # if SETUP_LOCAL_HOST is true then initialize the controller
  count    = var.SETUP_LOCAL_HOST ? 1 : 0
  filename = "${path.module}/scripts/setup-juju-env.sh"
  content = templatefile("${path.module}/scripts/setup-juju-env.tftpl", {
    project_id             = var.PROJECT_ID,
    region                 = var.REGION,
    zone                   = local.zone,
    network_name           = google_compute_network.main_vpc.name,
    controller_subnet_name = google_compute_subnetwork.controller_subnet.name,
    controller_constraints = var.CONTROLLER_CONSTRAINTS,
    gke_cluster_name       = var.GKE_CLUSTER_NAME,
    sa_email               = "",
    sa_key_path            = local_sensitive_file.juju_sa_key[0].filename,
  })
  depends_on = [
    google_container_cluster.gke,
    google_container_node_pool.gke_nodes,
    google_service_account.juju,
    google_project_iam_member.juju,
    local_sensitive_file.juju_sa_key,
    google_compute_network.main_vpc,
    google_compute_subnetwork.controller_subnet,
  ]
}

# Execute the script on the local host
resource "null_resource" "SETUP_LOCAL_HOST" {
  count = var.SETUP_LOCAL_HOST ? 1 : 0

  provisioner "local-exec" {
    command = "bash ${local_file.host_set_up_script[0].filename}"
  }

  depends_on = [
    google_container_cluster.gke,
    google_container_node_pool.gke_nodes,
    google_service_account.juju,
    google_project_iam_member.juju,
    google_service_account_iam_member.juju_act_as_default_compute,
    google_service_account_iam_member.juju_act_as_self,
    local_sensitive_file.juju_sa_key,
    google_compute_network.main_vpc,
    google_compute_subnetwork.controller_subnet,
    google_compute_subnetwork.deployments_subnet,
    google_compute_firewall.allow_external,
    google_compute_firewall.allow_internal,
    google_compute_router_nat.nat,
    local_file.host_set_up_script,
  ]
}
