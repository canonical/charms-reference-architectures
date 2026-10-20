# Copyright 2026 Canonical Ltd.
# See LICENSE file for licensing details.

variable "backups" {
  description = "Existing S3 bucket for backups."
  type = object({
    bucket = string
    region = string
    path   = optional(string, "opensearch-k8s")
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
  description = "Model name, risk, storage sizes and Traefik config for COS Lite."
  type = object({
    model                         = optional(string, "cos")
    grafana_storage_directives    = optional(map(string), { database = "1G" })
    loki_storage_directives       = optional(map(string), { active-index-directory = "1G", loki-chunks = "1G" })
    prometheus_storage_directives = optional(map(string), { database = "1G" })
    risk                          = optional(string, "stable")
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
    config   = optional(map(string), {})
    channel  = optional(string, "latest/stable")
    revision = optional(number)
  })
  default  = {}
  nullable = false
}

variable "k8s_cloud" {
  description = "Kubernetes cloud for both models."
  type        = string
  default     = "k8s"
}

variable "k8s_credential" {
  description = "Credential for `k8s_cloud`."
  type        = string
  default     = null
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
    resources          = optional(map(string), {})
    constraints        = optional(string)
    units              = optional(number, 3)
    storage_directives = optional(map(string), { opensearch-data = "20G" })
  })
  default  = {}
  nullable = false
}

variable "opensearch_dashboards" {
  description = "OpenSearch Dashboards app."
  type = object({
    config    = optional(map(string), {})
    channel   = optional(string)
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

variable "risk" {
  description = "Risk of the OpenSearch and OpenSearch Dashboards channels (`2/<risk>`) when their `channel` isn't set."
  type        = string
  default     = "edge"

  validation {
    condition     = contains(["edge", "beta", "candidate", "stable"], var.risk)
    error_message = "`risk` must be edge, beta, candidate or stable."
  }
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
