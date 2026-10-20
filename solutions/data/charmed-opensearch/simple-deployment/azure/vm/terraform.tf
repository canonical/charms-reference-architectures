# Copyright 2026 Canonical Ltd.
# See LICENSE file for licensing details.

terraform {
  required_version = ">= 1.12"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.75"
    }
    juju = {
      source  = "juju/juju"
      version = "~> 2.3"
    }
  }
}
