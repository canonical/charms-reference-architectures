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
  }
}

# Both providers read their credentials from the environment: the juju CLI or JUJU_* variables,
# and Application Default Credentials or GOOGLE_* variables.
provider "google" {
  project = var.gcp_project
}

provider "juju" {}
