# Copyright 2026 Canonical Ltd.
# See LICENSE file for licensing details.

variable "azure_container" {
  description = "Name of the blob container created for Valkey backups."
  type        = string
  default     = "valkey"
}

variable "azure_key_version" {
  description = "Version of the storage account key handed to azure-storage-integrator. Increment after renewing the primary key (az storage account keys renew) to push the new one."
  type        = number
  default     = 1

  validation {
    condition     = var.azure_key_version >= 1 && floor(var.azure_key_version) == var.azure_key_version
    error_message = "azure_key_version must be a whole number of at least 1."
  }
}

variable "azure_path" {
  description = "Blob prefix inside the container where Valkey writes backups."
  type        = string
  default     = "valkey"
}

variable "azure_resource_group" {
  description = "Existing resource group that holds the storage account. The account takes its location."
  type        = string
}

variable "azure_storage_account" {
  description = "Name of the storage account created for Valkey backups. Globally unique."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]{3,24}$", var.azure_storage_account))
    error_message = "azure_storage_account must be 3-24 characters and contain only lowercase letters and digits."
  }
}

variable "cos_model" {
  description = "Name of the model created for COS Lite."
  type        = string
  default     = "cos"
}

variable "k8s_cloud" {
  description = "Kubernetes cloud that hosts both models. null: the controller's default cloud."
  type        = string
  default     = null
}

variable "k8s_credential" {
  description = "Controller credential for k8s_cloud. null: a credential named like k8s_cloud, which is what juju add-k8s creates."
  type        = string
  default     = null
}

variable "load_balancer" {
  description = "Expose the Valkey primary on an AKS public load balancer with a static IP, reachable only from allowed_cidrs. aks_cluster and resource_group name the cluster behind k8s_cloud. network_security_group names the NSG on the node subnet, in resource_group, if there is one. null: no load balancer."
  type = object({
    allowed_cidrs          = list(string)
    aks_cluster            = string
    resource_group         = string
    network_security_group = optional(string)
  })
  default = null

  validation {
    condition = var.load_balancer == null || (
      length(var.load_balancer.allowed_cidrs) > 0 &&
      alltrue([for c in var.load_balancer.allowed_cidrs : can(cidrhost(c, 0))])
    )
    error_message = "load_balancer.allowed_cidrs must hold at least one valid CIDR, such as 203.0.113.4/32."
  }
}

variable "risk" {
  description = "Risk level of the Valkey, COS Lite and integrator channels (edge, beta, candidate or stable)."
  type        = string
  default     = "edge"
}

variable "valkey_model" {
  description = "Name of the model created for Valkey, its integrators and self-signed-certificates."
  type        = string
  default     = "valkey"
}
