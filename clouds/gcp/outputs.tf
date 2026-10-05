# Copyright 2026 Canonical Ltd.
# See LICENSE file for licensing details.

output "infrastructure" {
  description = "Key details of the created GCP infrastructure: project, network and subnet names, and the bastion public IP if provisioned."
  value = {
    project_id                      = var.PROJECT_ID
    network_name                    = google_compute_network.main_vpc.name
    controller_subnet_name          = google_compute_subnetwork.controller_subnet.name
    deployments_subnet_name         = google_compute_subnetwork.deployments_subnet.name
    deployments_peers_subnet_name   = google_compute_subnetwork.deployments_peers_subnet.name
    deployments_clients_subnet_name = google_compute_subnetwork.deployments_clients_subnet.name
    bastion_public_ip               = var.PROVISION_BASTION ? google_compute_address.bastion_public_ip[0].address : null
  }
}

output "gke_cluster" {
  description = "Details of the provisioned GKE cluster, or null if GKE_CLUSTER_NAME is empty."
  value = var.GKE_CLUSTER_NAME != "" ? {
    name           = google_container_cluster.gke[0].name
    location       = google_container_cluster.gke[0].location
    endpoint       = google_container_cluster.gke[0].endpoint
    ca_certificate = google_container_cluster.gke[0].master_auth[0].cluster_ca_certificate
  } : null
  sensitive = true
}
