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

variable "cos_ingress" {
  description = "Allow allowed_cidrs to reach COS Lite's Traefik on ports 80 and 443 through network_security_group, the NSG in resource_group on the AKS node subnet. List the Valkey machines' outbound IPs, such as their NAT gateway's, so the collector can push, and your own to reach Grafana. null: no rule."
  type = object({
    allowed_cidrs          = list(string)
    network_security_group = string
    resource_group         = string
  })
  default = null

  validation {
    condition = var.cos_ingress == null || (
      length(var.cos_ingress.allowed_cidrs) > 0 &&
      alltrue([for c in var.cos_ingress.allowed_cidrs : can(cidrhost(c, 0))])
    )
    error_message = "cos_ingress.allowed_cidrs must hold at least one valid CIDR, such as 203.0.113.4/32."
  }
}

variable "excluded_subnets" {
  description = "CIDRs of VNet subnets that the Valkey model's machines must stay out of, such as the controller's. They move to a separate space, and the model constraint spaces=alpha keeps every machine in the remaining subnets. []: machines go to any subnet."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for c in var.excluded_subnets : can(cidrhost(c, 0))])
    error_message = "excluded_subnets must hold valid CIDRs, such as 10.1.0.0/16."
  }
}

variable "external_access" {
  description = "Expose Valkey's TLS ports on the units' public IPs, reachable only from allowed_cidrs. extra_sans adds names or IPs, such as those public IPs, to every unit's server certificate. null: not exposed."
  type = object({
    allowed_cidrs = list(string)
    extra_sans    = optional(list(string), [])
  })
  default = null

  validation {
    condition = var.external_access == null || (
      length(var.external_access.allowed_cidrs) > 0 &&
      alltrue([for c in var.external_access.allowed_cidrs : can(cidrhost(c, 0))])
    )
    error_message = "external_access.allowed_cidrs must hold at least one valid CIDR, such as 203.0.113.4/32."
  }
}

variable "k8s_cloud" {
  description = "Kubernetes cloud on the controller that hosts the COS Lite model."
  type        = string
}

variable "k8s_credential" {
  description = "Controller credential for k8s_cloud. null: a credential named like k8s_cloud, which is what juju add-k8s creates."
  type        = string
  default     = null
}

variable "machine_cloud" {
  description = "Machine cloud that hosts the Valkey model. null: the controller's default cloud."
  type        = string
  default     = null
}

variable "machine_credential" {
  description = "Controller credential for machine_cloud. null: the controller's default credential for that cloud."
  type        = string
  default     = null
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
