# Copyright 2024 Canonical Ltd.
# See LICENSE file for licensing details.

terraform {
  required_version = ">= 1.6"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.89.0"
    }

    juju = {
      source  = "juju/juju"
      version = ">= 0.20.0"
    }

    random = {
      source  = "hashicorp/random"
      version = "~> 3.7.2"
    }
  }
}
