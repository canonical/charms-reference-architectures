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
  description = "The public key for SSH access"
  type        = string
  default     = null
  # Needs to be set if PROVISION_BASTION is true
  validation {
    condition     = var.PROVISION_BASTION == false || (var.PROVISION_BASTION == true && var.SSH_PUBLIC_KEY != null)
    error_message = "SSH_PUBLIC_KEY must be set if PROVISION_BASTION is true"
  }
}

variable "SOURCE_ADDRESS_PREFIXES" {
  description = "List of source address prefixes for the network security group rules"
  type        = list(string)
  default     = null
}

variable "AKS_CLUSTER_NAME" {
  description = "Name of the AKS cluster. Set to null to skip AKS provisioning."
  type        = string
  default     = "aks-cluster" # Set to empty string if you don't want to provision an AKS cluster
}

variable "INITIALIZE_HOST" {
  description = "Flag to initialize the host machine with juju and other tools"
  type        = bool
  default     = false
  validation {
    # Only if PROVISION_BASTION is false
    condition     = var.PROVISION_BASTION == false || var.INITIALIZE_HOST == false
    error_message = "Initialize host can only be set to true if PROVISION_BASTION is false"
  }
}
