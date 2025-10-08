# Copyright 2025 Canonical Ltd.
# See LICENSE file for licensing details.

variable "REGION" {
  type    = string
  default = "eu-central-1"
}

variable "PROVISION_BASTION" {
  description = "Flag to provision the bastion host"
  type        = bool
  default     = true
}

variable "SOURCE_ADDRESSES" {
  description = "List of IP addresses allowed to SSH into the bastion host"
  type        = list(string)
  default     = null
  # Needs to be set if PROVISION_BASTION is true
  validation {
    condition     = var.PROVISION_BASTION == false || (var.PROVISION_BASTION == true && var.SOURCE_ADDRESSES != null)
    error_message = "SOURCE_ADDRESSES must be set if PROVISION_BASTION is true"
  }
}

variable "SSH_KEY" {
  description = "The name of the public key for SSH access to the bastion"
  type        = string
  default     = null
  # Needs to be set if PROVISION_BASTION is true
  validation {
    condition     = var.PROVISION_BASTION == false || (var.PROVISION_BASTION == true && var.SSH_KEY != null)
    error_message = "SSH_KEY must be set if PROVISION_BASTION is true"
  }
}
