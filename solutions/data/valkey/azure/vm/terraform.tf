# Copyright 2026 Canonical Ltd.
# See LICENSE file for licensing details.

terraform {
  required_version = ">= 1.11"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 4.0"
    }
    juju = {
      source  = "juju/juju"
      version = ">= 2.2.1"
    }
  }
}

# Both providers read their credentials from the environment: the juju CLI or JUJU_* variables,
# and the Azure CLI login or ARM_* variables. ARM_SUBSCRIPTION_ID picks the subscription.
provider "azurerm" {
  features {}
}

provider "juju" {}
