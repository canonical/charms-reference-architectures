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
    bucket = "tftest-8923dc35-5e0b-4690-bf96-28cef7ebd099" # replace with actual bucket name
    key    = "state"
    region = "eu-central-1" # replace with your region
  }
}
