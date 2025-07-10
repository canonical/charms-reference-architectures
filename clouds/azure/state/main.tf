provider "azurerm" {
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }
  subscription_id = var.AZURE_SUBSCRIPTION_ID
}

# Create a resource group for storing the Terraform state
resource "azurerm_resource_group" "tfstate-rg" {
  name     = var.RESOURCE_GROUP_NAME
  location = var.REGION
}

# Generate a random suffix to ensure the storage account name is unique
resource "random_string" "suffix" {
  length  = 8
  special = false
  upper   = false
  lower   = true
  numeric = true
}

# Create a storage account for storing the Terraform state
resource "azurerm_storage_account" "tfstate-sa" {
  name                     = "${var.STORAGE_ACCOUNT_NAME}${random_string.suffix.result}"
  resource_group_name      = azurerm_resource_group.tfstate-rg.name
  location                 = azurerm_resource_group.tfstate-rg.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
}

# Create a container for the Terraform state files
resource "azurerm_storage_container" "tfstate-container" {
  name                  = "tfstate"
  storage_account_id    = azurerm_storage_account.tfstate-sa.id
  container_access_type = "private"
}

