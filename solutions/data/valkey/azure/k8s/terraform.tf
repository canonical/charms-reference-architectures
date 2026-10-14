# Copyright 2026 Canonical Ltd.
# See LICENSE file for licensing details.

terraform {
  required_version = ">= 1.11"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 4.0"
    }
    juju = {
      source  = "juju/juju"
      version = ">= 2.2.1"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.30"
    }
  }
}

# Both providers read their credentials from the environment: the juju CLI or JUJU_* variables,
# and the Azure CLI login or ARM_* variables. ARM_SUBSCRIPTION_ID picks the subscription.
provider "azurerm" {
  features {}
}

provider "juju" {}

# Only used with load_balancer set: reaches the AKS cluster with its local client certificate.
provider "kubernetes" {
  host                   = local.aks == null ? null : local.aks.kube_config[0].host
  client_certificate     = local.aks == null ? null : base64decode(local.aks.kube_config[0].client_certificate)
  client_key             = local.aks == null ? null : base64decode(local.aks.kube_config[0].client_key)
  cluster_ca_certificate = local.aks == null ? null : base64decode(local.aks.kube_config[0].cluster_ca_certificate)
}
