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

output "valkey_external_endpoint" {
  description = "Load balancer address of the Valkey primary (TLS, standalone mode). null without load_balancer."
  value       = var.load_balancer == null ? null : "${azurerm_public_ip.valkey[0].ip_address}:${module.valkey.credentials.valkey.tls_port}"
}

output "valkey" {
  description = "Valkey connection details and deployed components. No password: run the data-integrator get-credentials action for one."
  value = {
    components  = module.valkey.components
    credentials = module.valkey.credentials
    model_uuid  = module.valkey.models[var.valkey_model].model_uuid
  }
}
