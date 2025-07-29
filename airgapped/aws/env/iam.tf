# Copyright 2025 Canonical Ltd.
# See LICENSE file for licensing details.

resource "aws_iam_role" "imagebuilder_role" {
  name = "imagebuilder-ec2-role"

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

resource "aws_iam_policy" "imagebuilder_policy" {
  name = "imagebuilder-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "EC2AndSSM"
        Effect = "Allow"
        Action = [
          "ssm:GetParameter",
          "ssm:GetParameters",
          "ssm:GetParametersByPath",
          "ec2:DescribeInstances",
          "ec2:RunInstances",
          "ec2:TerminateInstances",
          "ec2:CreateTags",
          "ec2:DescribeImages",
          "ec2:CreateImage",
          "ec2:DeleteSnapshot",
          "ec2:DescribeSnapshots",
          "ec2:DescribeSecurityGroups",
          "ec2:DescribeSubnets",
          "ec2:DescribeVpcs",
          "iam:PassRole",
          "imagebuilder:GetComponent",
          "s3:GetObject",
          "s3:PutObject",
          "s3:ListBucket"
        ],
        Resource = "*"
      },
      {
        Sid    = "S3AccessForImageBuilder"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.imagebuilder_scripts_bucket.arn,
          "${aws_s3_bucket.imagebuilder_scripts_bucket.arn}/*"
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "imagebuilder_attach" {
  role       = aws_iam_role.imagebuilder_role.name
  policy_arn = aws_iam_policy.imagebuilder_policy.arn
}

resource "aws_iam_role_policy_attachment" "ssm_core_attach" {
  role       = aws_iam_role.imagebuilder_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "imagebuilder_profile" {
  name = "imagebuilder-instance-profile"
  role = aws_iam_role.imagebuilder_role.name
}
