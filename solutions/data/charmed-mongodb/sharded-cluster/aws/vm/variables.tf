# Copyright 2026 Canonical Ltd.
# See LICENSE file for licensing details.

variable "models" {
  description = "Names of the AWS models used for the config server and the two shards."
  type = object({
    config_server = optional(string, "mongodb-config")
    shard_one     = optional(string, "mongodb-shard-one")
    shard_two     = optional(string, "mongodb-shard-two")
  })
  default = {}

  validation {
    condition     = length(distinct([var.models.config_server, var.models.shard_one, var.models.shard_two])) == 3
    error_message = "The config server and each shard must use a different model."
  }
}

variable "config_server" {
  description = "MongoDB config-server application configuration."
  type = object({
    app_name    = optional(string, "config-server")
    base        = optional(string, "ubuntu@24.04")
    channel     = optional(string, "8/stable")
    config      = optional(map(string), { role = "config-server" })
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
    machines           = optional(set(string), [])
    revision           = optional(number, null)
    storage_directives = optional(map(string), {})
    units              = optional(number, 3)
  })
  default = {}
}

variable "mongos" {
  description = "Mongos application configuration."
  type = object({
    app_name = optional(string, "mongos")
    base     = optional(string, "ubuntu@24.04")
    channel  = optional(string, "8/stable")
    config   = optional(map(string), {})
    endpoint_bindings = optional(set(object({
      space    = string
      endpoint = optional(string)
    })), [])
    revision = optional(number, null)
  })
  default = {}
}

variable "shards" {
  description = "Configuration for the two MongoDB shards. The first shard is deployed in models.shard_one and the second in models.shard_two."
  type = list(object({
    app_name    = string
    base        = optional(string, "ubuntu@24.04")
    channel     = optional(string, "8/stable")
    config      = optional(map(string), { role = "shard" })
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
    machines           = optional(set(string), [])
    revision           = optional(number, null)
    storage_directives = optional(map(string), {})
    units              = optional(number, 3)
  }))
  default = [
    { app_name = "shard-one" },
    { app_name = "shard-two" },
  ]

  validation {
    condition     = length(var.shards) == 2
    error_message = "Exactly two shards must be configured."
  }

  validation {
    condition     = length(distinct([for shard in var.shards : shard.app_name])) == 2
    error_message = "Each shard must have a unique application name."
  }
}

variable "data_integrator" {
  description = "Data-integrator configuration. It is deployed in the config-server model."
  type = object({
    app_name    = optional(string, "data-integrator")
    base        = optional(string, "ubuntu@24.04")
    channel     = optional(string, "latest/edge")
    config      = optional(map(string), { database-name = "mongodb", extra-user-roles = "admin" })
    constraints = optional(string, "arch=amd64")
    endpoint_bindings = optional(set(object({
      space    = string
      endpoint = optional(string)
    })), [])
    machines           = optional(set(string), [])
    revision           = optional(number, null)
    storage_directives = optional(map(string), {})
    units              = optional(number, 1)
  })
  default = {}
}

variable "s3_integrator" {
  description = "Optional S3 integrator configuration. It is deployed in the config-server model."
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
    error_message = "The S3 integrator can be placed on at most one machine."
  }
}

variable "self_signed_certificates" {
  description = "Self-signed-certificates configuration. It is deployed in the config-server model."
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
  description = "Charmed etcd configuration. It is deployed in the config-server model."
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

variable "s3_access_key" {
  description = "Optional S3 access key."
  type        = string
  sensitive   = true
  default     = null
}

variable "s3_secret_key" {
  description = "Optional S3 secret key."
  type        = string
  sensitive   = true
  default     = null
}

variable "tls_client_private_key" {
  description = "Optional PEM private key for config-server client TLS."
  type        = string
  sensitive   = true
  default     = null
}

variable "tls_peer_private_key" {
  description = "Optional PEM private key for config-server peer TLS."
  type        = string
  sensitive   = true
  default     = null
}

variable "logging_config" {
  description = "Logging configuration used by the MongoDB sharded-cluster module."
  type        = string
  default     = "<root>=INFO"
}
