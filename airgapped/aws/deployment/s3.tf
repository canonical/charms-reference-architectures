# Copyright 2025 Canonical Ltd.
# See LICENSE file for licensing details.

resource "random_uuid" "s3_bucket_prefix" { }
resource "random_uuid" "s3_bucket_suffix" { }

locals {
  bucket_prefix = substr(replace(random_uuid.s3_bucket_prefix.result, "-", ""), 0, 10)
  bucket_suffix = substr(replace(random_uuid.s3_bucket_suffix.result, "-", ""), 0, 10)
}

resource "aws_s3_bucket" "backups_bucket" {
  bucket = "${local.bucket_prefix}-backups-${local.bucket_suffix}"
  force_destroy = true

  tags = {
    Name        = "Backups Scripts"
    Environment = "airgapped"
  }
}

resource "aws_s3_bucket_public_access_block" "s3_bucket_block_public_access" {
  bucket = aws_s3_bucket.backups_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
