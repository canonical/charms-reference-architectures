# Copyright 2026 Canonical Ltd.
# See LICENSE file for licensing details.

data "azurerm_resource_group" "backups" {
  name = var.azure_resource_group
}

resource "azurerm_storage_account" "backups" {
  name                            = var.azure_storage_account
  resource_group_name             = data.azurerm_resource_group.backups.name
  location                        = data.azurerm_resource_group.backups.location
  account_tier                    = "Standard"
  account_replication_type        = "LRS"
  allow_nested_items_to_be_public = false
}

resource "azurerm_storage_container" "backups" {
  name               = var.azure_container
  storage_account_id = azurerm_storage_account.backups.id
}
