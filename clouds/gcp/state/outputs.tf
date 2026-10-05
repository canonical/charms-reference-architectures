# Copyright 2026 Canonical Ltd.
# See LICENSE file for licensing details.

output "bucket_name" {
  description = "The name of the created GCS bucket for state files."
  value       = google_storage_bucket.tfstate.name
}
