# Copyright 2026 Canonical Ltd.
# See LICENSE file for licensing details.

terraform {
  required_version = ">= 1.11"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 6.0"
    }
    juju = {
      source  = "juju/juju"
      version = ">= 2.2.1"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.30"
    }
  }
}

# Both providers read their credentials from the environment: the juju CLI or JUJU_* variables,
# and Application Default Credentials or GOOGLE_* variables.
provider "google" {
  project = var.gcp_project
}

provider "juju" {}

# Only used with load_balancer set: reaches the GKE cluster with the google provider's token.
provider "kubernetes" {
  host                   = local.gke_cluster == null ? null : "https://${local.gke_cluster.endpoint}"
  cluster_ca_certificate = local.gke_cluster == null ? null : base64decode(local.gke_cluster.master_auth[0].cluster_ca_certificate)
  token                  = one(data.google_client_config.this[*].access_token)
}
