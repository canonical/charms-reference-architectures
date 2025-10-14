# Copyright 2025 Canonical Ltd.
# See LICENSE file for licensing details.

variable "REGION" {
  type    = string
  default = "eu-central-1"
}

variable "BUCKET_NAME" {
  description = "Name of the S3 storage bucket to be created"
  type        = string
  default     = null
  validation {
    condition     = var.BUCKET_NAME != null
    error_message = "BUCKET_NAME must be set"
  }
}