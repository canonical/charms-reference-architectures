# Copyright 2026 Canonical Ltd.
# See LICENSE file for licensing details.

## ====================================================
## Firewall rules
## ====================================================

# GCP firewalls allow all egress by default, so only ingress rules are needed.

# Applies to the bastion only, or to every instance on the local-host path.
# Juju's bootstrap also requires some rule in the network to allow tcp/22.
resource "google_compute_firewall" "allow_external" {
  name          = "main-vpc-allow-external"
  network       = google_compute_network.main_vpc.name
  direction     = "INGRESS"
  source_ranges = local.source_ranges
  target_tags   = var.PROVISION_BASTION ? ["bastion"] : null

  # SSH, Juju API, HTTP, HTTPS
  allow {
    protocol = "tcp"
    ports    = ["22", "17070", "80", "443"]
  }

  # Ping (ICMP)
  allow {
    protocol = "icmp"
  }
}

# Custom-mode VPCs have no implicit intra-network allow. Juju needs
# machine-to-controller traffic and GKE pods need to reach VM workloads.
resource "google_compute_firewall" "allow_internal" {
  name      = "main-vpc-allow-internal"
  network   = google_compute_network.main_vpc.name
  direction = "INGRESS"
  source_ranges = concat(
    [
      google_compute_subnetwork.controller_subnet.ip_cidr_range,
      google_compute_subnetwork.deployments_subnet.ip_cidr_range,
      google_compute_subnetwork.deployments_peers_subnet.ip_cidr_range,
      google_compute_subnetwork.deployments_clients_subnet.ip_cidr_range,
    ],
    google_compute_subnetwork.deployments_subnet.secondary_ip_range[*].ip_cidr_range,
  )

  allow {
    protocol = "all"
  }
}
