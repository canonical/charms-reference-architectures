# Copyright 2026 Canonical Ltd.
# See LICENSE file for licensing details.

variable "model_config" {
  description = "Configuration for Juju models."
  type = object({
    cloud      = optional(string, "aws")
    credential = optional(string, null)
  })
  default = {}
}

variable "models" {
  description = "Names of the AWS models used for the config server. Shard models are now configured per shard."
  type = object({
    config_server = optional(string, "mongodb-config")
  })
  default = {}
}
variable "vpc_id" {
  description = "Optional AWS VPC ID shared by the solution infrastructure. Juju applies it to the cluster models. This setting is immutable after model creation. Required if you use the `clouds/aws` module in this repository to configure the AWS cloud, since that module creates the Juju controller in a specific VPC. Leave unset if you manage your own AWS cloud configuration and Juju controller placement."
  type        = string
  default     = null

  validation {
    condition     = var.vpc_id == null || can(regex("^vpc-[0-9a-f]+$", var.vpc_id))
    error_message = "vpc_id must be a valid AWS VPC ID such as vpc-0123456789abcdef0."
  }
}

variable "cos" {
  description = "Configuration for the Charmed Observability Stack. Storage defaults are intended for testing and must be sized before production deployment."
  type = object({
    model_name                    = optional(string, "cos")
    cloud                         = optional(string, "k8s")
    credential                    = optional(string, "k8s")
    risk                          = optional(string, "stable")
    grafana_storage_directives    = optional(map(string), { database = "1G" })
    loki_storage_directives       = optional(map(string), { active-index-directory = "1G", loki-chunks = "1G" })
    prometheus_storage_directives = optional(map(string), { database = "1G" })
  })
  default = {}
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
  description = "Configuration for MongoDB shards. Each shard can specify its own model name or use auto-generated names."
  type = list(object({
    app_name           = string
    model_name         = optional(string) # If not specified, auto-generated as "mongodb-shard-{index+1}"
    base               = optional(string, "ubuntu@24.04")
    channel            = optional(string, "8/stable")
    config             = optional(map(string), { role = "shard" })
    constraints        = optional(string, "arch=amd64")
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
    condition     = length(var.shards) >= 1
    error_message = "At least one shard must be configured."
  }

  validation {
    condition     = length(distinct([for shard in var.shards : shard.app_name])) == length(var.shards)
    error_message = "Each shard must have a unique application name."
  }

  validation {
    condition = length(distinct([
      for i, shard in var.shards : 
      shard.model_name != null ? shard.model_name : "mongodb-shard-${i + 1}"
    ])) == length(var.shards)
    error_message = "Each shard must use a unique model name (explicit or auto-generated)."
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

variable "etcd" {
  description = "Charmed etcd configuration. It is deployed in a hardcoded 'mongodb-etcd' model using the etcd product module."
  type = object({
    app_name           = optional(string, "etcd")
    channel            = optional(string, "3.6/stable")
    revision           = optional(string, null)
    base               = optional(string, "ubuntu@24.04")
    constraints        = optional(string, "arch=amd64")
    config             = optional(map(string), {})
    storage            = optional(map(string), {})
    units              = optional(number, 3)
    endpoint_bindings  = optional(map(string), {})
    expose             = optional(bool, false)
  })
  default = {}
}

variable "self_signed_certificates" {
  description = "Self-signed-certificates application configuration for MongoDB TLS."
  type = object({
    app_name    = optional(string, "self-signed-certificates")
    base        = optional(string, "ubuntu@24.04")
    channel     = optional(string, "1/stable")
    config      = optional(map(string), { ca-common-name = "MongoDB CA" })
    constraints = optional(string, "arch=amd64")
    revision    = optional(number, null)
    units       = optional(number, 1)
  })
  default = {}
}

variable "opentelemetry_collector" {
  description = "OpenTelemetry Collector configuration for observability integration."
  type = object({
    enabled     = optional(bool, false)
    app_name    = optional(string, "opentelemetry-collector")
    base        = optional(string, "ubuntu@24.04")
    channel     = optional(string, "2/stable")
    config      = optional(map(string), {})
    revision    = optional(number, null)
    constraints = optional(string, "arch=amd64")
  })
  default = {}
}

# Integration variables

variable "ldap_integration" {
  description = "Optional existing LDAP offer. Must be configured together with ldap_certificate_transfer_integration."
  type = object({
    url = string
  })
  default = null

  validation {
    condition     = var.ldap_integration == null ? true : var.ldap_integration.url != ""
    error_message = "ldap_integration.url must not be empty."
  }
}

variable "ldap_certificate_transfer_integration" {
  description = "Optional existing LDAP certificate transfer offer. Must be configured together with ldap_integration."
  type = object({
    url = string
  })
  default = null

  validation {
    condition     = var.ldap_certificate_transfer_integration == null ? true : var.ldap_certificate_transfer_integration.url != ""
    error_message = "ldap_certificate_transfer_integration.url must not be empty."
  }
}

variable "vault_kv_integration" {
  description = "Optional existing Vault KV offer for MongoDB encryption at rest."
  type = object({
    url = string
  })
  default = null

  validation {
    condition     = var.vault_kv_integration == null ? true : var.vault_kv_integration.url != ""
    error_message = "vault_kv_integration.url must not be empty."
  }
}


# Configuration variables

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
