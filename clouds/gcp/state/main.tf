# Copyright 2026 Canonical Ltd.
# See LICENSE file for licensing details.

provider "google" {
  project = var.PROJECT_ID
  region  = var.REGION
}

# Generate a random suffix to ensure the bucket name is unique
resource "random_string" "suffix" {
  length  = 8
  special = false
  upper   = false
  lower   = true
  numeric = true
}

# Create a bucket for storing the Terraform state
resource "google_storage_bucket" "tfstate" {
  name                        = "${var.BUCKET_NAME}${random_string.suffix.result}"
  location                    = var.REGION
  uniform_bucket_level_access = true
  # The state holds secrets, such as the Juju service account key on the
  # local-host path
  public_access_prevention = "enforced"

  versioning {
    enabled = true
  }
}
