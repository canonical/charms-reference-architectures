# Copyright 2025 Canonical Ltd.
# See LICENSE file for licensing details.

variable "RESOURCE_GROUP_NAME" {
  description = "The name of the Azure resource group"
  type        = string
  default     = "main-rg" # Default resource group name
}

variable "REGION" {
  type    = string
  default = "eastus"
}

variable "AZURE_SUBSCRIPTION_ID" {
  type      = string
  sensitive = true
}

variable "PROVISION_BASTION" {
  description = "Flag to provision the bastion host"
  type        = bool
  default     = true
}

variable "SSH_PUBLIC_KEY" {
  description = "The path to the public key for SSH access to the bastion"
  type        = string
  default     = null
  # Needs to be set if PROVISION_BASTION is true
  validation {
    condition     = var.PROVISION_BASTION == false || (var.PROVISION_BASTION == true && var.SSH_PUBLIC_KEY != null)
    error_message = "SSH_PUBLIC_KEY must be set if PROVISION_BASTION is true"
  }
}

variable "SSH_PRIVATE_KEY" {
  description = "The path to the private key for SSH access to the bastion"
  type        = string
  default     = null
  # Needs to be set if PROVISION_BASTION is true
  validation {
    condition     = var.PROVISION_BASTION == false || (var.PROVISION_BASTION == true && var.SSH_PRIVATE_KEY != null)
    error_message = "SSH_PRIVATE_KEY must be set if PROVISION_BASTION is true"
  }

}

variable "SOURCE_ADDRESSES" {
  description = "A list of CIDR blocks (e.g., `[\"1.2.3.4/32\", \"5.6.7.0/24\"]`) or service tags (e.g., `[\"VirtualNetwork\", \"AzureLoadBalancer\"]`) allowed for inbound NSG rules"
  type        = list(string)
  default     = null
}

variable "AKS_CLUSTER_NAME" {
  description = "Name of the AKS cluster. Set to null to skip AKS provisioning."
  type        = string
  default     = "aks-cluster" # Set to empty string if you don't want to provision an AKS cluster
}

variable "SETUP_LOCAL_HOST" {
  description = "Flag to initialize the host machine with juju and other tools"
  type        = bool
  default     = false
  validation {
    # Only if PROVISION_BASTION is false
    condition     = var.PROVISION_BASTION == false || var.SETUP_LOCAL_HOST == false
    error_message = "Initialize host can only be set to true if PROVISION_BASTION is false"
  }
}
