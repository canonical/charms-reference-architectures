# Copyright 2024 Canonical Ltd.
# See LICENSE file for licensing details.

# Roles
resource "aws_iam_role" "bastion_role" {
  name               = "bastion-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role" "juju_controller_role" {
  name               = "juju-controller-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role" "juju_unit_role" {
  name               = "juju-unit-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}

# policies
resource "aws_iam_role_policy" "bastion_policy" {
  name = "bastion-inline-policy"
  role = aws_iam_role.bastion_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "AllowEC2AndIAMBasic"
      Effect = "Allow"
      Action = [
        "ec2:*",
        "iam:GetInstanceProfile",
        "iam:ListInstanceProfiles",
        "iam:PassRole"
      ]
      Resource = "*"
    }]
  })
}

resource "aws_iam_role_policy" "juju_controller_policy" {
  name = "juju-controller-inline-policy"
  role = aws_iam_role.juju_controller_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "ControllerEC2AndIAMSSM"
      Effect = "Allow"
      Action = [
        "ec2:*",
        "iam:*",
        "ssm:*"
      ]
      Resource = "*"
    }]
  })
}

resource "aws_iam_role_policy" "juju_unit_policy" {
  name = "juju-unit-inline-policy"
  role = aws_iam_role.juju_unit_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "EC2DescribeBasics"
        Effect = "Allow"
        Action = [
          "ec2:DescribeInstances",
          "ec2:DescribeTags"
        ]
        Resource = "*"
      },
      {
        Sid    = "S3BackupRestore"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.backups_bucket.arn,
          "${aws_s3_bucket.backups_bucket.arn}/*"
        ]
      },
      {
        Sid    = "SSMAgentRuntime"
        Effect = "Allow"
        Action = [
          "ssm:UpdateInstanceInformation",
          "ssm:ListInstanceAssociations",
          "ssm:DescribeInstanceProperties",
          "ssm:GetParameters",
          "ssm:GetParameter"
        ]
        Resource = "*"
      }
    ]
  })

  depends_on = [aws_s3_bucket.backups_bucket]
}


# instance profiles
resource "aws_iam_instance_profile" "bastion_instance_profile" {
  name = "bastion-instance-profile"
  role = aws_iam_role.bastion_role.name
}

resource "aws_iam_instance_profile" "juju_controller_instance_profile" {
  name = "juju-controller-instance-profile"
  role = aws_iam_role.juju_controller_role.name
}

resource "aws_iam_instance_profile" "juju_unit_instance_profile" {
  name = "juju-unit-instance-profile"
  role = aws_iam_role.juju_unit_role.name
}
