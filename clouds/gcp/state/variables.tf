# Copyright 2026 Canonical Ltd.
# See LICENSE file for licensing details.

variable "PROJECT_ID" {
  description = "The ID of the GCP project where the state bucket will be created"
  type        = string
}

variable "REGION" {
  type    = string
  default = "us-central1"
}

variable "BUCKET_NAME" {
  description = "The name prefix of the GCS bucket for Terraform state"
  type        = string
  default     = "tfstate" # Default bucket name prefix. A random suffix will be added to ensure uniqueness.
}
