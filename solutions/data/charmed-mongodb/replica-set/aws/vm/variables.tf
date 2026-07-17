# Copyright 2026 Canonical Ltd.
# See LICENSE file for licensing details.

variable "mongodb_model" {
  description = "Name of the AWS VM model."
  type        = string
  default     = "mongodb"
}

variable "cos" {
  description = "Configuration for the Charmed Observability Stack."
  type = object({
    model      = optional(string, "cos")
    cloud      = optional(string, "k8s")
    credential = optional(string, "k8s")
    channel    = optional(string, null)
  })
  default = {}
}

variable "mongodb" {
  description = "MongoDB replica-set application configuration."
  type = object({
    app_name    = optional(string, "mongodb")
    base        = optional(string, "ubuntu@24.04")
    channel     = optional(string, "8/stable")
    config      = optional(map(string), { role = "replication" })
    constraints = optional(string, "arch=amd64")
    endpoint_bindings = optional(set(object({
      space    = string
      endpoint = optional(string)
    })), [])
    expose = optional(list(object({
      cidrs     = optional(string)
      endpoints = optional(string)
      spaces    = optional(string)
    })), [])
    machines           = optional(set(string), null)
    revision           = optional(number, null)
    storage_directives = optional(map(string), {})
    units              = optional(number, 3)
  })
  default = {}
}

variable "data_integrator" {
  description = "Data-integrator application configuration."
  type = object({
    app_name    = optional(string, "data-integrator")
    base        = optional(string, "ubuntu@24.04")
    channel     = optional(string, "latest/stable")
    config      = optional(map(string), { database-name = "mongodb", extra-user-roles = "admin" })
    constraints = optional(string, "arch=amd64")
    endpoint_bindings = optional(set(object({
      space    = string
      endpoint = optional(string)
    })), [])
    machines           = optional(set(string), null)
    revision           = optional(number, null)
    storage_directives = optional(map(string), {})
    units              = optional(number, 1)
  })
  default = {}
}

variable "backups_integrator" {
  description = "Optional S3 or GCS backup integrator configuration."
  type = object({
    storage_type = optional(string, "s3")
    config       = map(string)
    channel      = optional(string, null)
    base         = optional(string, "ubuntu@24.04")
    revision     = optional(number, null)
    constraints  = optional(string, "arch=amd64")
    machines     = optional(set(string), [])
  })
  default = null

  validation {
    condition     = var.backups_integrator == null || contains(["s3", "gcs"], var.backups_integrator.storage_type)
    error_message = "backups_integrator.storage_type must be either \"s3\" or \"gcs\"."
  }

  validation {
    condition     = var.backups_integrator == null || length(var.backups_integrator.machines) <= 1
    error_message = "The backup integrator can be placed on at most one machine."
  }
}

variable "gcs_secret_key" {
  description = "Optional GCP service-account JSON key used by the GCS integrator."
  type        = string
  sensitive   = true
  default     = null
}

variable "s3_access_key" {
  description = "Optional AWS S3 access key."
  type        = string
  sensitive   = true
  default     = null
}

variable "s3_secret_key" {
  description = "Optional AWS S3 secret key."
  type        = string
  sensitive   = true
  default     = null
}

variable "tls_client_private_key" {
  description = "Optional PEM private key for MongoDB client-to-server TLS certificates."
  type        = string
  sensitive   = true
  default     = null
}

variable "tls_peer_private_key" {
  description = "Optional PEM private key for MongoDB peer-to-peer TLS certificates."
  type        = string
  sensitive   = true
  default     = null
}

variable "self_signed_certificates" {
  description = "Self-signed-certificates application configuration."
  type = object({
    app_name    = optional(string, "self-signed-certificates")
    channel     = optional(string, "1/stable")
    revision    = optional(number, null)
    base        = optional(string, "ubuntu@24.04")
    constraints = optional(string, "arch=amd64")
    config      = optional(map(string), { ca-common-name = "MongoDB CA" })
  })
  default = {}
}

variable "etcd" {
  description = "Charmed etcd application configuration for MongoDB rolling operations."
  type = object({
    app_name           = optional(string, "charmed-etcd")
    channel            = optional(string, "3.6/stable")
    revision           = optional(number, null)
    base               = optional(string, "ubuntu@24.04")
    constraints        = optional(string, "arch=amd64")
    config             = optional(map(string), {})
    storage_directives = optional(map(string), {})
    units              = optional(number, 3)
  })
  default = {}
}

variable "vault" {
  description = "Vault application configuration for MongoDB encryption at rest."
  type = object({
    app_name           = optional(string, "vault")
    channel            = optional(string, "1.19/stable")
    revision           = optional(number, null)
    base               = optional(string, "ubuntu@24.04")
    constraints        = optional(string, "arch=amd64")
    config             = optional(map(string), {})
    storage_directives = optional(map(string), {})
    units              = optional(number, 1)
  })
  default = {}
}

variable "opentelemetry_collector" {
  description = "OpenTelemetry Collector subordinate application configuration."
  type = object({
    app_name    = optional(string, "opentelemetry-collector")
    channel     = optional(string, "2/stable")
    revision    = optional(number, null)
    base        = optional(string, "ubuntu@24.04")
    constraints = optional(string, "arch=amd64")
    config      = optional(map(string), {})
  })
  default = {}
}
