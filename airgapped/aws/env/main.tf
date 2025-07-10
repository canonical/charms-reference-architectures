# Copyright 2024 Canonical Ltd.
# See LICENSE file for licensing details.

provider "aws" {
  region = var.region
}

terraform {
  backend "s3" {
    bucket = "xyz-airgapped-env-tfstate-abc"
    key    = "env.tfstate"
    region = "us-east-1"
  }
}
