# Copyright 2026 Canonical Ltd.
# See LICENSE file for licensing details.

## ====================================================
## Network infra
## ====================================================

resource "google_compute_network" "main_vpc" {
  name                    = "main-vpc"
  auto_create_subnetworks = false

  depends_on = [google_project_service.compute]
}

resource "google_compute_subnetwork" "controller_subnet" {
  name                     = "controller-subnet"
  region                   = var.REGION
  network                  = google_compute_network.main_vpc.id
  ip_cidr_range            = "10.1.0.0/24"
  private_ip_google_access = true
}

# General-purpose subnet, also hosts the GKE nodes. The secondary ranges are
# used by the VPC-native GKE cluster for pods and services.
resource "google_compute_subnetwork" "deployments_subnet" {
  name                     = "deployments-subnet"
  region                   = var.REGION
  network                  = google_compute_network.main_vpc.id
  ip_cidr_range            = "10.2.0.0/24"
  private_ip_google_access = true

  secondary_ip_range {
    range_name    = "gke-pods"
    ip_cidr_range = "10.2.64.0/18"
  }

  secondary_ip_range {
    range_name    = "gke-services"
    ip_cidr_range = "10.2.32.0/20"
  }
}

# Subnets for binding Juju spaces such as "peers" and "clients".
# deployments_subnet stays the general-purpose subnet, also used by GKE.
resource "google_compute_subnetwork" "deployments_peers_subnet" {
  name                     = "deployments-peers-subnet"
  region                   = var.REGION
  network                  = google_compute_network.main_vpc.id
  ip_cidr_range            = "10.3.0.0/24"
  private_ip_google_access = true
}

resource "google_compute_subnetwork" "deployments_clients_subnet" {
  name                     = "deployments-clients-subnet"
  region                   = var.REGION
  network                  = google_compute_network.main_vpc.id
  ip_cidr_range            = "10.4.0.0/24"
  private_ip_google_access = true
}

# --- Cloud NAT ---
# One regional NAT gives every subnet (and the GKE pod range) private egress.
resource "google_compute_router" "nat_router" {
  name    = "main-nat-router"
  region  = var.REGION
  network = google_compute_network.main_vpc.id
}

resource "google_compute_router_nat" "nat" {
  name                               = "main-nat"
  region                             = var.REGION
  router                             = google_compute_router.nat_router.name
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"
}
