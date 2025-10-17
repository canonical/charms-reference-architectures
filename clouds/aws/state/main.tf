# Copyright 2025 Canonical Ltd.
# See LICENSE file for licensing details.

provider "aws" {
  region = var.REGION
}

resource "aws_s3_bucket" "terraform_state" {
  bucket = var.BUCKET_NAME
}

resource "aws_s3_bucket_ownership_controls" "control" {
  bucket = aws_s3_bucket.terraform_state.id
  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

resource "aws_s3_bucket_acl" "bucket_acl" {
  bucket = aws_s3_bucket.terraform_state.id
  acl    = "private"

  depends_on = [aws_s3_bucket.terraform_state, aws_s3_bucket_ownership_controls.control]
}

resource "aws_s3_bucket_versioning" "bucket_version" {
  bucket = aws_s3_bucket.terraform_state.id
  versioning_configuration {
    status = "Enabled"
  }

  depends_on = [aws_s3_bucket.terraform_state]
}
