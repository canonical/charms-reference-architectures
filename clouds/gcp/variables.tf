# Copyright 2026 Canonical Ltd.
# See LICENSE file for licensing details.

variable "PROJECT_ID" {
  description = "The ID of the GCP project where resources will be created"
  type        = string
}

variable "REGION" {
  type    = string
  default = "us-central1"
}

variable "ZONE" {
  description = "Zone of the bastion and the GKE cluster. Unset means the module looks up the first available zone of REGION on the first apply and keeps it."
  type        = string
  default     = null

  validation {
    condition     = var.ZONE == null || startswith(coalesce(var.ZONE, "-"), "${var.REGION}-")
    error_message = "ZONE must be a zone of REGION (e.g. us-central1-a)."
  }
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
  description = "A list of CIDR blocks (e.g., `[\"1.2.3.4/32\", \"5.6.7.0/24\"]`) allowed for inbound firewall rules and the GKE control plane public endpoint. Unset means unrestricted."
  type        = list(string)
  default     = null
}

variable "GKE_CLUSTER_NAME" {
  description = "Name of the GKE cluster. Set to an empty string to skip GKE provisioning."
  type        = string
  default     = "gke-cluster"

  validation {
    condition     = var.GKE_CLUSTER_NAME == "" || can(regex("^[a-z](?:[-a-z0-9]{0,38}[a-z0-9])?$", var.GKE_CLUSTER_NAME))
    error_message = "GKE_CLUSTER_NAME must be at most 40 characters of lowercase letters, digits and hyphens, start with a letter and not end with a hyphen."
  }
}

variable "GKE_NODE_COUNT" {
  description = "Number of nodes in the GKE node pool."
  type        = number
  default     = 3

  validation {
    condition     = var.GKE_NODE_COUNT >= 1
    error_message = "GKE_NODE_COUNT must be at least 1."
  }
}

variable "GKE_NODE_MACHINE_TYPE" {
  description = "Machine type for the GKE node pool. Choose a type with enough persistent-disk attachments for persistent workloads. Use n2-standard-4 for smaller workloads"
  type        = string
  default     = "n2-standard-16"
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

variable "CONTROLLER_CONSTRAINTS" {
  description = "Juju constraints used when provisioning the controller machine. The default pins a widely available type, since cores/mem constraints make Juju pick the cheapest match, often a new machine family that is out of capacity."
  type        = string
  default     = "instance-type=e2-standard-4"
}
