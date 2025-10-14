# Copyright 2025 Canonical Ltd.
# See LICENSE file for licensing details.

terraform {
  required_version = ">= 1.6"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~>6.15.0"
    }

    local = {
      source  = "hashicorp/local"
      version = "~>2.5.3"
    }

    null = {
      source  = "hashicorp/null"
      version = "~>3.2.4"
    }
  }

  backend "s3" {
    bucket = "my-bucket-name" # replace with actual bucket name
    key    = "state"
    region = var.REGION
  }
}