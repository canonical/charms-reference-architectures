# Copyright 2026 Canonical Ltd.
# See LICENSE file for licensing details.

locals {
  create_service_account = var.gcs_service_account_email == null

  service_account_email = local.create_service_account ? google_service_account.valkey_backup[0].email : var.gcs_service_account_email

  # The generated key, or the supplied one. Ephemeral when supplied, so it only reaches the
  # product module's write-only Juju secret.
  service_account_key = local.create_service_account ? base64decode(google_service_account_key.valkey_backup[0].private_key) : var.gcs_service_account_key
}

resource "google_storage_bucket" "backups" {
  name     = var.gcs_bucket
  location = var.gcs_location

  public_access_prevention    = "enforced"
  uniform_bucket_level_access = true
}

resource "google_service_account" "valkey_backup" {
  count = local.create_service_account ? 1 : 0

  # Service-account IDs allow 6-30 characters and must start with a letter.
  account_id   = "valkey-backup-${substr(md5(var.gcs_bucket), 0, 8)}"
  display_name = "Valkey backups to gs://${var.gcs_bucket}"
}

resource "google_service_account_key" "valkey_backup" {
  count              = local.create_service_account ? 1 : 0
  service_account_id = google_service_account.valkey_backup[0].name

  keepers = {
    version = var.gcs_key_version
  }
}

# The charm only needs object access: it falls back to listing when bucket creation is forbidden.
resource "google_storage_bucket_iam_member" "valkey_backup" {
  bucket = google_storage_bucket.backups.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${local.service_account_email}"
}
