# Copyright 2025 Canonical Ltd.
# See LICENSE file for licensing details.

terraform {
  required_version = ">= 1.6"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~>4.0"
    }

    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 3.4.0"
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

  # set up backend configuration to use Azure Storage Account
  backend "azurerm" {
    resource_group_name  = "tfstate-rg"
    storage_account_name = "tfstate8lbos2zx" # TODO replace this with a valid storage account name
    container_name       = "tfstate"
    key                  = "infra.terraform.tfstate"
  }
}
