# Copyright 2026 Canonical Ltd.
# See LICENSE file for licensing details.

terraform {
  required_version = ">= 1.12"

  required_providers {
    external = {
      source  = "hashicorp/external"
      version = ">= 2.0"
    }
    google = {
      source  = "hashicorp/google"
      version = ">= 8.7.0"
    }
    juju = {
      source  = "juju/juju"
      version = "~> 2.3"
    }
  }
}
