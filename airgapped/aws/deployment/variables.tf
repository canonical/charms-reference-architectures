# Copyright 2024 Canonical Ltd.
# See LICENSE file for licensing details.

variable "region" {
  type        = string
  description = "The region were the aws deployment will be performed."
  default     = "us-east-1"
}

# variable "team" {
#   type        = string
#   description = "The team for which the environment was set up."
# }

variable "vpn_client_public_key" {
  type        = string
  description = "The public key of the vpn client for accessing the vpn server."
}