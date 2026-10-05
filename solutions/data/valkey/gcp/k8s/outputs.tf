# Copyright 2026 Canonical Ltd.
# See LICENSE file for licensing details.

output "cos_model_uuid" {
  description = "UUID of the COS Lite model."
  value       = module.cos.model_uuid
}

output "cos_offers" {
  description = "COS Lite offer URLs, keyed by offer."
  value       = { for k, v in module.cos.offers : k => v.url }
}

output "gcs" {
  description = "Backup bucket and the service account that writes to it."
  value = {
    bucket                = google_storage_bucket.backups.name
    path                  = var.gcs_path
    service_account_email = local.service_account_email
  }
}

output "valkey_external_endpoint" {
  description = "Load balancer address of the Valkey primary (TLS, standalone mode). null without load_balancer."
  value       = var.load_balancer == null ? null : "${google_compute_address.valkey[0].address}:${module.valkey.credentials.valkey.tls_port}"
}

output "valkey" {
  description = "Valkey connection details and deployed components. No password: run the data-integrator get-credentials action for one."
  value = {
    components  = module.valkey.components
    credentials = module.valkey.credentials
    model_uuid  = module.valkey.models[var.valkey_model].model_uuid
  }
}
