# Copyright 2026 Canonical Ltd.
# See LICENSE file for licensing details.

variable "apps" {
  description = "Non-orchestrator OpenSearch apps."
  type = list(object({
    app_name           = string
    config             = optional(map(string), {})
    constraints        = optional(string)
    units              = optional(number, 3)
    storage_directives = optional(map(string), { opensearch-data = "20G" })
    model              = optional(string)
  }))
  default  = [{ app_name = "data", config = { roles = "data" } }]
  nullable = false

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
  description = "Existing S3 bucket for backups."
  type = object({
    bucket = string
    region = string
    path   = optional(string, "opensearch-k8s-ld")
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
  description = "Model name, storage sizes and Traefik config for COS Lite."
  type = object({
    model                         = optional(string, "cos")
    grafana_storage_directives    = optional(map(string), { database = "1G" })
    loki_storage_directives       = optional(map(string), { active-index-directory = "1G", loki-chunks = "1G" })
    prometheus_storage_directives = optional(map(string), { database = "1G" })
    traefik_config                = optional(map(string), {})
  })
  default = {}
}

variable "dashboards_traefik" {
  description = "Config for Traefik fronting OpenSearch Dashboards."
  type = object({
    config = optional(map(string), {})
    certificates_integration = optional(object({
      url = string
    }))
  })
  default  = {}
  nullable = false
}

variable "data_integrator" {
  description = "`data-integrator` configuration options."
  type = object({
    config = optional(map(string), {})
  })
  default  = {}
  nullable = false
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
    constraints        = optional(string)
    units              = optional(number, 3)
    storage_directives = optional(map(string), { opensearch-data = "20G" })
    model              = optional(string)
  })
  default = {}

  validation {
    condition     = try(var.failover.model, null) == null || contains(var.extra_models, try(var.failover.model, ""))
    error_message = "`failover.model` must be one of `extra_models`."
  }
}

variable "k8s_cloud" {
  description = "Kubernetes cloud for all models."
  type        = string
  default     = "k8s"
}

variable "k8s_credential" {
  description = "Credential for `k8s_cloud`."
  type        = string
  default     = null
}

variable "main" {
  description = "Main orchestrator app."
  type = object({
    config             = optional(map(string), {})
    constraints        = optional(string)
    units              = optional(number, 3)
    storage_directives = optional(map(string), { opensearch-data = "20G" })
  })
  default  = {}
  nullable = false
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
    channel   = optional(string, "2/edge")
    profile   = optional(string, "testing")
    revision  = optional(number)
    resources = optional(map(string), {})
  })
  default  = {}
  nullable = false
}

variable "opensearch_dashboards" {
  description = "OpenSearch Dashboards app."
  type = object({
    config    = optional(map(string), {})
    channel   = optional(string, "2/edge")
    revision  = optional(number)
    resources = optional(map(string), {})
    units     = optional(number, 3)
    tls       = optional(bool, true)
  })
  default  = {}
  nullable = false
}

variable "opensearch_model" {
  description = "Name of the model created for OpenSearch."
  type        = string
  default     = "opensearch"
}

variable "s3_access_key" {
  description = "S3 access key for `backups`."
  type        = string
  sensitive   = true
  ephemeral   = true
  default     = null
}

variable "s3_secret_key" {
  description = "S3 secret key for `backups`."
  type        = string
  sensitive   = true
  ephemeral   = true
  default     = null
}

variable "s3_secret_version" {
  description = "Version of the S3 keys. Increment to rotate them."
  type        = number
  default     = 1

  validation {
    condition     = var.s3_secret_version >= 1 && floor(var.s3_secret_version) == var.s3_secret_version
    error_message = "`s3_secret_version` must be a whole number of at least 1."
  }
}
