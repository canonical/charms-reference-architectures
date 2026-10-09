# Copyright 2026 Canonical Ltd.
# See LICENSE file for licensing details.

output "azure_storage" {
  description = "Backup storage account, container and path."
  value = {
    storage_account = azurerm_storage_account.backups.name
    container       = azurerm_storage_container.backups.name
    path            = var.azure_path
  }
}

output "cos_model_uuid" {
  description = "UUID of the COS Lite model."
  value       = module.cos.model_uuid
}

output "cos_offers" {
  description = "COS Lite offer URLs, keyed by offer."
  value       = { for k, v in module.cos.offers : k => v.url }
}

output "valkey" {
  description = "Valkey connection details and deployed components. No password: run the data-integrator get-credentials action for one."
  value = {
    components  = module.valkey.components
    credentials = module.valkey.credentials
    model_uuid  = juju_model.valkey.uuid
  }
}
