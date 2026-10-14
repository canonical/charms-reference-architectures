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

output "s3" {
  description = "Backup bucket and the IAM user that writes to it."
  value = {
    bucket   = aws_s3_bucket.backups.id
    path     = var.s3_path
    iam_user = aws_iam_user.valkey_backup.name
  }
}

output "valkey" {
  description = "Valkey connection details and deployed components. No password: run the data-integrator get-credentials action for one."
  value = {
    components  = module.valkey.components
    credentials = module.valkey.credentials
    model_uuid  = juju_model.valkey.uuid
  }
}
