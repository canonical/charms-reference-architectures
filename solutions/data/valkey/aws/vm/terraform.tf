# Copyright 2026 Canonical Ltd.
# See LICENSE file for licensing details.

terraform {
  required_version = ">= 1.11"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0"
    }
    juju = {
      source  = "juju/juju"
      version = ">= 2.2.1"
    }
  }
}

# Both providers read their credentials from the environment: the juju CLI or JUJU_* variables,
# and the AWS CLI profile or AWS_* variables.
provider "aws" {
  region = var.aws_region
}

provider "juju" {}
