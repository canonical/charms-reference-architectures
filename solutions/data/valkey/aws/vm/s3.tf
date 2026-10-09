# Copyright 2026 Canonical Ltd.
# See LICENSE file for licensing details.

resource "aws_s3_bucket" "backups" {
  bucket = var.s3_bucket
}

resource "aws_s3_bucket_public_access_block" "backups" {
  bucket = aws_s3_bucket.backups.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_iam_user" "valkey_backup" {
  name = "valkey-backup-${substr(md5(var.s3_bucket), 0, 8)}"
}

# The charm calls CreateBucket on every start and only accepts "already exists" answers, so the
# user needs CreateBucket on this bucket. S3 then answers BucketAlreadyOwnedByYou.
resource "aws_iam_user_policy" "valkey_backup" {
  name = "valkey-backup"
  user = aws_iam_user.valkey_backup.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:CreateBucket", "s3:GetBucketLocation", "s3:ListBucket"]
        Resource = aws_s3_bucket.backups.arn
      },
      {
        Effect   = "Allow"
        Action   = ["s3:AbortMultipartUpload", "s3:DeleteObject", "s3:GetObject", "s3:PutObject"]
        Resource = "${aws_s3_bucket.backups.arn}/*"
      },
    ]
  })
}

resource "terraform_data" "s3_key_version" {
  input = var.s3_key_version
}

# A new s3_key_version replaces the key: the new one reaches s3-integrator before the old one is
# deleted.
resource "aws_iam_access_key" "valkey_backup" {
  user = aws_iam_user.valkey_backup.name

  lifecycle {
    create_before_destroy = true
    replace_triggered_by  = [terraform_data.s3_key_version]
  }
}
