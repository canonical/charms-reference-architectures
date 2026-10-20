# Copyright 2026 Canonical Ltd.
# See LICENSE file for licensing details.

variable "apps" {
  description = "Non-orchestrator OpenSearch apps."
  type = list(object({
    app_name           = string
    config             = optional(map(string), {})
    constraints        = optional(string, "cores=2 mem=8G")
    units              = optional(number, 3)
    storage_directives = optional(map(string), {})
    allowed_cidrs      = optional(list(string), ["10.0.0.0/8"])
    model              = optional(string)
  }))
  default  = [{ app_name = "data", config = { roles = "data" } }]
  nullable = false

  validation {
    condition     = alltrue(flatten([for app in var.apps : [for cidr in app.allowed_cidrs : can(cidrhost(cidr, 0))]]))
    error_message = "`apps[*].allowed_cidrs` must hold valid CIDRs."
  }

  validation {
    condition     = alltrue([for app in var.apps : app.model == null || contains(var.extra_models, app.model)])
    error_message = "`apps[*].model` must be one of `extra_models`."
  }

  validation {
    condition = !anytrue([
      for config in concat([var.main.config], var.failover == null ? [] : [var.failover.config], [for app in var.apps : app.config]) :
      contains(keys(config), "profile")
    ])
    error_message = "Set `opensearch_charm.profile` instead of `config.profile`."
  }
}

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
    path            = optional(string, "opensearch-vm-ld")
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
  description = "Kubernetes cloud, credential, model name, storage sizes and Traefik config for COS Lite."
  type = object({
    cloud                         = optional(string, "k8s")
    credential                    = optional(string)
    model                         = optional(string, "cos")
    grafana_storage_directives    = optional(map(string), { database = "1G" })
    loki_storage_directives       = optional(map(string), { active-index-directory = "1G", loki-chunks = "1G" })
    prometheus_storage_directives = optional(map(string), { database = "1G" })
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
    config = optional(map(string), {})
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

variable "extra_models" {
  description = "Names of extra models for OpenSearch apps."
  type        = list(string)
  default     = []
  nullable    = false

  validation {
    condition     = length(distinct(var.extra_models)) == length(var.extra_models)
    error_message = "`extra_models` must not repeat a name."
  }

  validation {
    condition     = !contains(var.extra_models, var.opensearch_model)
    error_message = "`extra_models` can't contain `opensearch_model`."
  }
}

variable "failover" {
  description = "Failover orchestrator app."
  type = object({
    config             = optional(map(string), {})
    constraints        = optional(string, "cores=2 mem=8G")
    units              = optional(number, 3)
    storage_directives = optional(map(string), {})
    allowed_cidrs      = optional(list(string), ["10.0.0.0/8"])
    model              = optional(string)
  })
  default = {}

  validation {
    condition     = var.failover == null || alltrue([for cidr in try(var.failover.allowed_cidrs, []) : can(cidrhost(cidr, 0))])
    error_message = "`failover.allowed_cidrs` must hold valid CIDRs."
  }

  validation {
    condition     = try(var.failover.model, null) == null || contains(var.extra_models, try(var.failover.model, ""))
    error_message = "`failover.model` must be one of `extra_models`."
  }
}

variable "integrator_constraints" {
  description = "Constraints for integrator apps."
  type        = string
  default     = "cores=1 mem=2G"
}

variable "main" {
  description = "Main orchestrator app."
  type = object({
    config             = optional(map(string), {})
    constraints        = optional(string, "cores=2 mem=8G")
    units              = optional(number, 3)
    storage_directives = optional(map(string), {})
    allowed_cidrs      = optional(list(string), ["10.0.0.0/8"])
  })
  default  = {}
  nullable = false

  validation {
    condition     = alltrue([for cidr in var.main.allowed_cidrs : can(cidrhost(cidr, 0))])
    error_message = "`main.allowed_cidrs` must hold valid CIDRs."
  }
}

variable "model_constraints" {
  description = "Constraints of the OpenSearch models."
  type        = string
  default     = "allocate-public-ip=false"
  nullable    = false
}

variable "network" {
  description = "Existing Azure VNet for the OpenSearch models and the OpenSearch Dashboards load balancer, as `<resource group>/<name>`."
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

variable "opensearch_charm" {
  description = "OpenSearch charm for all OpenSearch apps."
  type = object({
    channel  = optional(string, "2/edge")
    profile  = optional(string, "testing")
    revision = optional(number)
  })
  default  = {}
  nullable = false
}

variable "opensearch_dashboards" {
  description = "OpenSearch Dashboards app."
  type = object({
    config        = optional(map(string), {})
    channel       = optional(string, "2/edge")
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
