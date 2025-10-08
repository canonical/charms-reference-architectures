# Copyright 2025 Canonical Ltd.
# See LICENSE file for licensing details.

variable "REGION" {
  type    = string
  default = "eu-central-1"
}

variable "SOURCE_ADDRESSES" {
  description = "List of IP addresses allowed to SSH into the bastion host"
  type        = list(string)
  default     = null
  validation {
    condition     = var.SOURCE_ADDRESSES != null
    error_message = "SOURCE_ADDRESSES must be set"
  }
}

variable "SSH_KEY" {
  description = "The name of the public key for SSH access to the bastion"
  type        = string
  default     = null
  validation {
    condition     = var.SSH_KEY != null
    error_message = "SSH_KEY must be set"
  }
}

variable "ACCESS_KEY" {
  description = "Access key for AWS account"
  type        = string
  default     = null
  validation {
    condition     = var.ACCESS_KEY != null
    error_message = "ACCESS_KEY must be set"
  }
}

variable "SECRET_KEY" {
  description = "Secret key for AWS account"
  type        = string
  default     = null
  validation {
    condition     = var.SECRET_KEY != null
    error_message = "SECRET_KEY must be set"
  }
}
