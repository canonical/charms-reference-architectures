# Copyright 2026 Canonical Ltd.
# See LICENSE file for licensing details.

variable "azure_storage_secret_key" {
  description = "Access key of the storage account in `backups`."
  type        = string
  sensitive   = true
  ephemeral   = true
  default     = null
}

variable "azure_storage_secret_version" {
  description = "Version of the storage account key. Increment to rotate it."
  type        = number
  default     = 1

  validation {
    condition     = var.azure_storage_secret_version >= 1 && floor(var.azure_storage_secret_version) == var.azure_storage_secret_version
    error_message = "`azure_storage_secret_version` must be a whole number of at least 1."
  }
}

variable "backups" {
  description = "Existing Azure storage container for backups."
  type = object({
    storage_account = string
    container       = string
    path            = optional(string, "opensearch-vm")
    config          = optional(map(string), {})
  })
  default = null
}

variable "certificates_integration" {
  description = "Optional offer of an external TLS provider for OpenSearch and OpenSearch Dashboards."
  type = object({
    url = string
  })
  default = null
}

variable "cos" {
  description = "Kubernetes cloud, credential, model name, risk, storage sizes and Traefik config for COS Lite."
  type = object({
    cloud                         = optional(string, "k8s")
    credential                    = optional(string)
    model                         = optional(string, "cos")
    grafana_storage_directives    = optional(map(string), { database = "1G" })
    loki_storage_directives       = optional(map(string), { active-index-directory = "1G", loki-chunks = "1G" })
    prometheus_storage_directives = optional(map(string), { database = "1G" })
    risk                          = optional(string, "stable")
    traefik_config                = optional(map(string), {})
  })
  default = {}
}

variable "dashboards_load_balancer" {
  description = "OpenSearch Dashboards load balancer. Private by default; `public = true` exposes it to `allowed_cidrs`."
  type = object({
    public                = optional(bool, false)
    allowed_cidrs         = optional(list(string), [])
    subnet                = optional(string, "deployments-subnet")
    subnet_cidr           = optional(string, "10.5.0.0/24")
    dns_name              = optional(string)
    key_vault_secret_id   = optional(string)
    key_vault_identity_id = optional(string)
    ca_certificate        = optional(string)
  })
  default = {}

  validation {
    condition = var.dashboards_load_balancer == null ? true : (
      !var.dashboards_load_balancer.public || try(trimspace(var.dashboards_load_balancer.key_vault_secret_id) != "", false)
    )
    error_message = "Public access requires `key_vault_secret_id`."
  }

  validation {
    condition     = try((length(var.dashboards_load_balancer.allowed_cidrs) > 0) == var.dashboards_load_balancer.public, true)
    error_message = "Set at least one CIDR in `allowed_cidrs` with `public = true`, and none without it."
  }

  validation {
    condition     = try((var.dashboards_load_balancer.key_vault_secret_id == null) == (var.dashboards_load_balancer.key_vault_identity_id == null), true)
    error_message = "Set `key_vault_secret_id` and `key_vault_identity_id` together."
  }

  validation {
    condition     = try(var.dashboards_load_balancer.ca_certificate != null || var.dashboards_load_balancer.key_vault_secret_id == null || var.certificates_integration == null || !var.opensearch_dashboards.tls, true)
    error_message = "`key_vault_secret_id` with `certificates_integration` needs `ca_certificate`."
  }

  validation {
    condition     = try(strcontains(var.dashboards_load_balancer.dns_name, "."), true)
    error_message = "`dns_name` needs at least two labels, like `dashboards.internal`."
  }
}

variable "data_integrator" {
  description = "`data-integrator` configuration options."
  type = object({
    config   = optional(map(string), {})
    channel  = optional(string, "latest/stable")
    revision = optional(number)
  })
  default  = {}
  nullable = false
}

variable "excluded_subnets" {
  description = "CIDRs of subnets that machines must stay out of."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for cidr in var.excluded_subnets : can(cidrhost(cidr, 0))])
    error_message = "`excluded_subnets` must hold valid CIDRs."
  }
}

variable "integrator_constraints" {
  description = "Constraints for integrator apps."
  type        = string
  default     = "cores=1 mem=2G"
}

variable "model_constraints" {
  description = "Constraints of the OpenSearch model."
  type        = string
  default     = "allocate-public-ip=false"
  nullable    = false
}

variable "network" {
  description = "Existing Azure VNet for the OpenSearch model and the OpenSearch Dashboards load balancer, as `<resource group>/<name>`."
  type        = string
  default     = "main-rg/main-vnet"
  nullable    = false

  validation {
    condition     = can(regex("^[^/]+/[^/]+$", var.network))
    error_message = "`network` must be `<resource group>/<name>`."
  }
}

variable "offered_endpoints" {
  description = "OpenSearch endpoints to offer to other models."
  type        = list(string)
  default     = []
  nullable    = false
}

variable "opensearch" {
  description = "OpenSearch app."
  type = object({
    config             = optional(map(string), {})
    channel            = optional(string)
    revision           = optional(number)
    constraints        = optional(string, "cores=2 mem=8G")
    units              = optional(number, 3)
    storage_directives = optional(map(string), { opensearch-data = "20G" })
    allowed_cidrs      = optional(list(string), ["10.0.0.0/8"])
  })
  default  = {}
  nullable = false

  validation {
    condition     = alltrue([for cidr in var.opensearch.allowed_cidrs : can(cidrhost(cidr, 0))])
    error_message = "`opensearch.allowed_cidrs` must hold valid CIDRs."
  }
}

variable "opensearch_dashboards" {
  description = "OpenSearch Dashboards app."
  type = object({
    config        = optional(map(string), {})
    channel       = optional(string)
    revision      = optional(number)
    constraints   = optional(string, "cores=2 mem=4G")
    units         = optional(number, 3)
    tls           = optional(bool, true)
    allowed_cidrs = optional(list(string), ["10.0.0.0/8"])
  })
  default  = {}
  nullable = false

  validation {
    condition     = alltrue([for cidr in var.opensearch_dashboards.allowed_cidrs : can(cidrhost(cidr, 0))])
    error_message = "`opensearch_dashboards.allowed_cidrs` must hold valid CIDRs."
  }
}

variable "opensearch_model" {
  description = "Name of the model created for OpenSearch."
  type        = string
  default     = "opensearch"
}

variable "risk" {
  description = "Risk of the OpenSearch and OpenSearch Dashboards channels (`2/<risk>`) when their `channel` isn't set."
  type        = string
  default     = "edge"

  validation {
    condition     = contains(["edge", "beta", "candidate", "stable"], var.risk)
    error_message = "`risk` must be edge, beta, candidate or stable."
  }
}
