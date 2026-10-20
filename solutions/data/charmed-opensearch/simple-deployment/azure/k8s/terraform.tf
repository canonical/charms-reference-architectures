# Copyright 2026 Canonical Ltd.
# See LICENSE file for licensing details.

terraform {
  required_version = ">= 1.12"

  required_providers {
    juju = {
      source  = "juju/juju"
      version = "~> 2.2"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 3.0"
    }
  }
}
