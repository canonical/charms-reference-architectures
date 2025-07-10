# Copyright 2025 Canonical Ltd.
# See LICENSE file for licensing details.

## ====================================================
## Provider Configuration
## ====================================================

provider "azurerm" {
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }
  subscription_id = var.AZURE_SUBSCRIPTION_ID
}

## ====================================================
## Base Resources
## ====================================================
resource "azurerm_resource_group" "main_rg" {
  name     = var.RESOURCE_GROUP_NAME
  location = var.REGION
}

