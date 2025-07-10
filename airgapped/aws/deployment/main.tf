# Copyright 2024 Canonical Ltd.
# See LICENSE file for licensing details.

provider "aws" {
  region = var.region
}


data "terraform_remote_state" "amis_networking" {
  backend = "s3"
  config = {
    bucket = "xyz-airgapped-env-tfstate-abc"
    key    = "env.tfstate"
    region = var.region
  }
}
