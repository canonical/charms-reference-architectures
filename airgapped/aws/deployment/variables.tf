# Copyright 2024 Canonical Ltd.
# See LICENSE file for licensing details.

variable "region" {
  description = "The region were the aws deployment will be performed."
  default     = "us-east-1"
}

variable "team" {
  description = "The team for which the environment was set up."
}

variable "vpn_client_public_key" {
  description = "The public key of the vpn client for accessing the vpn server."
}