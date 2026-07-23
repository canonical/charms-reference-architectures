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
    risk       = optional(string, "stable")
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

variable "s3_integrator" {
  description = "Optional S3 backup integrator configuration."
  type = object({
    config      = map(string)
    channel     = optional(string, "2/stable")
    base        = optional(string, "ubuntu@24.04")
    revision    = optional(number, null)
    constraints = optional(string, "arch=amd64")
    machines    = optional(set(string), [])
  })
  default = null

  validation {
    condition     = var.s3_integrator == null || length(var.s3_integrator.machines) <= 1
    error_message = "The backup integrator can be placed on at most one machine."
  }
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


variable "vault_kv_integration" {
  description = "Existing Vault KV integration target for MongoDB encryption at rest. Use kind = \"endpoint\" with name/endpoint for a Vault application in the MongoDB model, or kind = \"offer\" with url for a cross-model offer."
  type = object({
    kind     = string
    name     = optional(string, null)
    endpoint = optional(string, null)
    url      = optional(string, null)
  })

  validation {
    condition     = contains(["endpoint", "offer"], var.vault_kv_integration.kind)
    error_message = "vault_kv_integration.kind must be either \"endpoint\" or \"offer\"."
  }

  validation {
    condition = (
      var.vault_kv_integration.kind != "endpoint" ||
      (
        var.vault_kv_integration.name != null &&
        var.vault_kv_integration.name != "" &&
        var.vault_kv_integration.endpoint != null &&
        var.vault_kv_integration.endpoint != ""
      )
    )
    error_message = "For kind = \"endpoint\", both name and endpoint must be provided."
  }

  validation {
    condition = (
      var.vault_kv_integration.kind != "offer" ||
      (
        var.vault_kv_integration.url != null &&
        var.vault_kv_integration.url != ""
      )
    )
    error_message = "For kind = \"offer\", url must be provided."
  }
}

variable "logging_config" {
  description = "Logging configuration used by the MongoDB replica-set module."
  type        = string
  default     = "<root>=INFO"
}
