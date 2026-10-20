# Copyright 2026 Canonical Ltd.
# See LICENSE file for licensing details.

variable "backups" {
  description = "Existing S3 bucket for backups."
  type = object({
    bucket = string
    region = string
    path   = optional(string, "opensearch-vm")
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
    certificate_arn = optional(string)
    dns_name        = optional(string)
    public          = optional(bool, false)
    subnet_ids      = optional(set(string), [])
    allowed_cidrs   = optional(set(string), [])
  })
  default = {}

  validation {
    condition     = var.dashboards_load_balancer == null ? true : var.dashboards_load_balancer.public || length(var.opensearch_dashboards.allowed_cidrs) > 0
    error_message = "A private load balancer needs `opensearch_dashboards.allowed_cidrs` for backend access."
  }

  validation {
    condition = var.dashboards_load_balancer == null ? true : (
      !var.dashboards_load_balancer.public || try(trimspace(var.dashboards_load_balancer.certificate_arn) != "", false)
    )
    error_message = "Public OpenSearch Dashboards access requires a non-empty `certificate_arn`."
  }

  validation {
    condition = var.dashboards_load_balancer == null ? true : (
      var.dashboards_load_balancer.public ? length(var.dashboards_load_balancer.allowed_cidrs) > 0 : length(var.dashboards_load_balancer.allowed_cidrs) == 0
    )
    error_message = "Set at least one CIDR in `allowed_cidrs` with `public = true`, and none without it."
  }

  validation {
    condition = var.dashboards_load_balancer == null ? true : (
      !var.dashboards_load_balancer.public || length(var.dashboards_load_balancer.subnet_ids) > 0
    )
    error_message = "Public access requires explicit `subnet_ids` with routes to an internet gateway, one subnet per availability zone."
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
  default     = ["10.0.10.0/24", "10.0.11.0/24"] # Excludes the public subnets.

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
  default     = ""
  nullable    = false
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
    channel            = optional(string, "2/edge")
    revision           = optional(number)
    constraints        = optional(string, "cores=2 mem=8G")
    units              = optional(number, 3)
    storage_directives = optional(map(string), { opensearch-data = "20G" })
    allowed_cidrs      = optional(list(string), ["10.0.0.0/16"])
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
    channel       = optional(string, "2/edge")
    revision      = optional(number)
    constraints   = optional(string, "cores=2 mem=4G")
    units         = optional(number, 3)
    tls           = optional(bool, true)
    allowed_cidrs = optional(list(string), ["10.0.0.0/16"])
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

variable "vpc_id" {
  description = "VPC of the Juju models."
  type        = string
}
