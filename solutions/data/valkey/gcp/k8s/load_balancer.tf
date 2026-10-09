# Copyright 2026 Canonical Ltd.
# See LICENSE file for licensing details.

locals {
  gke_cluster = one(data.google_container_cluster.this[*])
  valkey_app  = module.valkey.credentials.valkey.app_name

  # Regional address in the cluster's region: drop the zone suffix of a zonal location.
  lb_region = var.load_balancer == null ? null : regex("^[a-z]+-[a-z]+[0-9]+", var.load_balancer.gke_location)
}

data "google_container_cluster" "this" {
  count    = var.load_balancer == null ? 0 : 1
  name     = var.load_balancer.gke_cluster
  location = var.load_balancer.gke_location
}

data "google_client_config" "this" {
  count = var.load_balancer == null ? 0 : 1
}

resource "google_compute_address" "valkey" {
  count        = var.load_balancer == null ? 0 : 1
  name         = "${var.valkey_model}-valkey-external"
  region       = local.lb_region
  address_type = "EXTERNAL"
}

# Follows the primary: the charm moves the role=primary pod label on failover.
resource "kubernetes_service_v1" "valkey_external" {
  count = var.load_balancer == null ? 0 : 1

  metadata {
    name      = "${local.valkey_app}-external"
    namespace = var.valkey_model # Juju names the namespace after the model.
  }

  spec {
    type                        = "LoadBalancer"
    load_balancer_ip            = google_compute_address.valkey[0].address
    load_balancer_source_ranges = var.load_balancer.allowed_cidrs

    selector = {
      application-name = local.valkey_app
      role             = "primary"
    }

    port {
      name        = "valkey-tls"
      port        = module.valkey.credentials.valkey.tls_port
      target_port = module.valkey.credentials.valkey.tls_port
    }
  }
}
