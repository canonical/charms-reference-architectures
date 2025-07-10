
output "resource_group_name" {
  description = "The name of the created Azure Resource Group."
  value = {
    name     = azurerm_resource_group.tfstate-rg.name
    location = azurerm_resource_group.tfstate-rg.location
  }
}

output "storage_account_name" {
  description = "The name of the created Azure Storage Account."
  value       = azurerm_storage_account.tfstate-sa.name
}

output "storage_container_name" {
  description = "The name of the created Azure Blob Container for state files."
  value       = azurerm_storage_container.tfstate-container.name
}
