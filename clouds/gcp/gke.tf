# Copyright 2026 Canonical Ltd.
# See LICENSE file for licensing details.

## ====================================================
## Kubernetes infra (GKE)
## ====================================================

# Dedicated node service account instead of the default compute engine
# account, which is over-privileged and can be blocked by org policy
resource "google_service_account" "gke_nodes" {
  # if GKE_CLUSTER_NAME is not set, do not create the GKE cluster
  count        = var.GKE_CLUSTER_NAME != "" ? 1 : 0
  account_id   = "gke-nodes"
  display_name = "GKE node service account"

  depends_on = [google_project_service.iam]
}

resource "google_project_iam_member" "gke_nodes" {
  count   = var.GKE_CLUSTER_NAME != "" ? 1 : 0
  project = var.PROJECT_ID
  role    = "roles/container.defaultNodeServiceAccount"
  member  = "serviceAccount:${google_service_account.gke_nodes[0].email}"

  depends_on = [google_project_service.cloudresourcemanager]
}

resource "google_container_cluster" "gke" {
  # if GKE_CLUSTER_NAME is not set, do not create the GKE cluster
  count = var.GKE_CLUSTER_NAME != "" ? 1 : 0
  name  = var.GKE_CLUSTER_NAME
  # Zonal: on a regional cluster node counts are per zone
  location = local.zone

  network    = google_compute_network.main_vpc.id
  subnetwork = google_compute_subnetwork.deployments_subnet.id

  # The default node pool is replaced by google_container_node_pool below.
  # initial_node_count must still be at least 1.
  remove_default_node_pool = true
  initial_node_count       = 1
  deletion_protection      = false

  # Keeps the short-lived default pool off the default compute account.
  # ignore_changes stops a cluster replacement once that pool is gone.
  node_config {
    service_account = google_service_account.gke_nodes[0].email
    oauth_scopes    = ["https://www.googleapis.com/auth/cloud-platform"]
  }

  # VPC-native cluster using the secondary ranges of the deployments subnet
  ip_allocation_policy {
    cluster_secondary_range_name  = "gke-pods"
    services_secondary_range_name = "gke-services"
  }

  # Private nodes (egress through Cloud NAT), public control plane endpoint
  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = false
  }

  # Restrict the control plane when SOURCE_ADDRESSES is set. GKE enforces this
  # list on the private endpoint too, so every subnet that talks to the K8s API
  # needs to be in it: the controller's, and the deployment subnets', because
  # machine units read cross-model secrets offered from K8s straight from the API.
  dynamic "master_authorized_networks_config" {
    for_each = var.SOURCE_ADDRESSES == null ? [] : [1]
    content {
      # Allows all Google Cloud IPs. Only the local-host path needs it, because
      # its controller reaches the public endpoint from a Google Cloud IP.
      gcp_public_cidrs_access_enabled = var.SETUP_LOCAL_HOST

      dynamic "cidr_blocks" {
        for_each = concat(var.SOURCE_ADDRESSES, [
          google_compute_subnetwork.controller_subnet.ip_cidr_range,
          google_compute_subnetwork.deployments_subnet.ip_cidr_range,
          google_compute_subnetwork.deployments_peers_subnet.ip_cidr_range,
          google_compute_subnetwork.deployments_clients_subnet.ip_cidr_range,
        ])
        content {
          cidr_block = cidr_blocks.value
        }
      }
    }
  }

  lifecycle {
    ignore_changes = [node_config]
  }

  depends_on = [
    google_project_service.container,
    google_project_iam_member.gke_nodes,
  ]
}

resource "google_container_node_pool" "gke_nodes" {
  count = var.GKE_CLUSTER_NAME != "" ? 1 : 0
  name  = "primary-pool"
  # Required alongside a zonal cluster referenced by name, otherwise the
  # provider looks the cluster up in the region
  location   = local.zone
  cluster    = google_container_cluster.gke[0].name
  node_count = var.GKE_NODE_COUNT

  node_config {
    machine_type    = var.GKE_NODE_MACHINE_TYPE
    service_account = google_service_account.gke_nodes[0].email
  }

  depends_on = [google_project_iam_member.gke_nodes]
}
