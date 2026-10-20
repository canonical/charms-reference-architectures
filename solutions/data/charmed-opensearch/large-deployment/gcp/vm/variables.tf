# Copyright 2026 Canonical Ltd.
# See LICENSE file for licensing details.

variable "apps" {
  description = "Non-orchestrator OpenSearch apps."
  type = list(object({
    app_name           = string
    config             = optional(map(string), {})
    constraints        = optional(string, "instance-type=e2-standard-2")
    units              = optional(number, 3)
    storage_directives = optional(map(string), { opensearch-data = "20G" })
    allowed_cidrs      = optional(list(string), [])
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

variable "backups" {
  description = "Existing GCS bucket for backups."
  type = object({
    bucket = string
    path   = optional(string, "opensearch-vm-ld")
    config = optional(map(string), {})
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
    subnet              = optional(string, "deployments-clients-subnet")
    backend_subnet      = optional(string, "deployments-subnet")
    proxy_subnet_cidr   = optional(string, "10.5.0.0/23")
    create_proxy_subnet = optional(bool, true)
    certificate_id      = optional(string)
    dns_name            = optional(string)
    public              = optional(bool, false)
    security_policy     = optional(string)
    allowed_cidrs       = optional(set(string), [])
  })
  default = {}

  validation {
    condition     = var.dashboards_load_balancer == null ? true : trimspace(var.dashboards_load_balancer.backend_subnet) != ""
    error_message = "`backend_subnet` must be a non-empty subnet name in the selected network and region."
  }

  validation {
    condition = var.dashboards_load_balancer == null ? true : (
      !var.dashboards_load_balancer.public || try(trimspace(var.dashboards_load_balancer.certificate_id) != "", false)
    )
    error_message = "Public OpenSearch Dashboards access requires a non-empty `certificate_id`."
  }

  validation {
    condition = var.dashboards_load_balancer == null ? true : (
      var.dashboards_load_balancer.public ? (
        (var.dashboards_load_balancer.security_policy != null) != (length(var.dashboards_load_balancer.allowed_cidrs) > 0)
        ) : (
        var.dashboards_load_balancer.security_policy == null && length(var.dashboards_load_balancer.allowed_cidrs) == 0
      )
    )
    error_message = "For public access, supply either `security_policy` or non-empty `allowed_cidrs`, not both. These settings apply only to public access."
  }

  validation {
    condition = var.dashboards_load_balancer == null ? true : (
      var.dashboards_load_balancer.security_policy == null ? true : trimspace(var.dashboards_load_balancer.security_policy) != ""
    )
    error_message = "`security_policy` must be a non-empty regional Cloud Armor policy reference."
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
    constraints        = optional(string, "instance-type=e2-standard-2")
    units              = optional(number, 3)
    storage_directives = optional(map(string), { opensearch-data = "20G" })
    allowed_cidrs      = optional(list(string), [])
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

variable "gcs_secret_key" {
  description = "GCS service-account key for `backups`."
  type        = string
  sensitive   = true
  ephemeral   = true
  default     = null
}

variable "gcs_secret_version" {
  description = "Version of the GCS key. Increment to rotate it."
  type        = number
  default     = 1

  validation {
    condition     = var.gcs_secret_version >= 1 && floor(var.gcs_secret_version) == var.gcs_secret_version
    error_message = "`gcs_secret_version` must be a whole number of at least 1."
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
    constraints        = optional(string, "instance-type=e2-standard-2")
    units              = optional(number, 3)
    storage_directives = optional(map(string), { opensearch-data = "20G" })
    allowed_cidrs      = optional(list(string), [])
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
  description = "Existing GCP network for the OpenSearch models and the OpenSearch Dashboards load balancer."
  type        = string
  default     = "main-vpc"
  nullable    = false

  validation {
    condition     = trimspace(var.network) != ""
    error_message = "`network` must be a non-empty GCP network name."
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
    constraints   = optional(string, "instance-type=e2-medium")
    units         = optional(number, 3)
    tls           = optional(bool, true)
    allowed_cidrs = optional(list(string), [])
  })
  default  = {}
  nullable = false

  validation {
    condition = var.dashboards_load_balancer == null || (
      var.opensearch_dashboards.units >= 1 && var.opensearch_dashboards.units <= 50 &&
      floor(var.opensearch_dashboards.units) == var.opensearch_dashboards.units
    )
    error_message = "With an OpenSearch Dashboards load balancer, `opensearch_dashboards.units` must be between 1 and 50."
  }

  validation {
    condition     = alltrue([for cidr in var.opensearch_dashboards.allowed_cidrs : can(cidrhost(cidr, 0))])
    error_message = "`opensearch_dashboards.allowed_cidrs` must hold valid CIDRs."
  }

  validation {
    condition     = var.dashboards_load_balancer == null || length(regexall("(^|\\s)spaces=", var.opensearch_dashboards.constraints)) == 0
    error_message = "With an OpenSearch Dashboards load balancer, use `dashboards_load_balancer.backend_subnet` instead of a `spaces=` constraint."
  }
}

variable "opensearch_model" {
  description = "Name of the model created for OpenSearch."
  type        = string
  default     = "opensearch"
}
