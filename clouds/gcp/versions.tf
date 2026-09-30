# Copyright 2026 Canonical Ltd.
# See LICENSE file for licensing details.

terraform {
  # Cross-variable validation conditions (see variables.tf) need Terraform 1.9+
  required_version = ">= 1.9"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 8.0"
    }

    local = {
      source  = "hashicorp/local"
      version = "~> 2.9"
    }

    null = {
      source  = "hashicorp/null"
      version = "~> 3.3"
    }
  }

  # set up backend configuration to use a GCS bucket
  backend "gcs" {
    bucket = "tfstateXXXXXXXX" # TODO replace this with the bucket name from the state module
    prefix = "state"
  }
}
