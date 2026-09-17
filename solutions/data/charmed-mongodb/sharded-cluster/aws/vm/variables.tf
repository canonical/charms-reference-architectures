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
  description = "Names of the AWS models used for the MongoDB deployment. The number of shard models must match the number of shards configured."
  type = object({
    config_server = optional(string, "mongodb-config")
    shards        = optional(list(string), ["mongodb-shard-one", "mongodb-shard-two"])
  })
  default = {}

  validation {
    condition     = length(var.models.shards) >= 1
    error_message = "At least one shard model must be configured."
  }

  validation {
    condition     = length(distinct(concat([var.models.config_server], var.models.shards))) == length(var.models.shards) + 1
    error_message = "All model names (config server and shards) must be unique."
  }
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

variable "network_spaces" {
  description = "CIDRs of the existing AWS subnets assigned to the peer and client Juju spaces in the config-server and shard models."
  type = object({
    peers_cidr   = optional(string, "10.0.2.0/24")
    clients_cidr = optional(string, "10.0.3.0/24")
  })
  default = {}

  validation {
    condition = (
      var.network_spaces.peers_cidr != var.network_spaces.clients_cidr &&
      can(cidrnetmask(var.network_spaces.peers_cidr)) &&
      can(cidrnetmask(var.network_spaces.clients_cidr))
    )
    error_message = "Peer and client CIDRs must be distinct and valid IPv4 network addresses."
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
    constraints = optional(string, "arch=amd64 spaces=peers")
    endpoint_bindings = optional(set(object({
      space    = string
      endpoint = optional(string)
      })), [
      {
        endpoint = "database-peers"
        space    = "peers"
      },
      {
        endpoint = "config-server"
        space    = "peers"
      },
    ])
    expose = optional(list(object({
      cidrs     = optional(string)
      endpoints = optional(string)
      spaces    = optional(string)
      })), [
      {
        cidrs     = "10.0.2.0/24"
        endpoints = "config-server"
        spaces    = "peers"
      },
    ])
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
  description = "Configuration for MongoDB shards. Each shard will be deployed in the corresponding model from models.shards (matched by index)."
  type = list(object({
    app_name    = string
    base        = optional(string, "ubuntu@24.04")
    channel     = optional(string, "8/stable")
    config      = optional(map(string), { role = "shard" })
    constraints = optional(string, "arch=amd64 spaces=peers")
    endpoint_bindings = optional(set(object({
      space    = string
      endpoint = optional(string)
      })), [
      {
        endpoint = "database-peers"
        space    = "peers"
      },
      {
        endpoint = "sharding"
        space    = "peers"
      },
    ])
    expose = optional(list(object({
      cidrs     = optional(string)
      endpoints = optional(string)
      spaces    = optional(string)
      })), [
      {
        cidrs     = "10.0.2.0/24"
        endpoints = "sharding"
        spaces    = "peers"
      },
    ])
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
}

variable "data_integrator" {
  description = "Data-integrator configuration. It is deployed in the config-server model."
  type = object({
    app_name    = optional(string, "data-integrator")
    base        = optional(string, "ubuntu@24.04")
    channel     = optional(string, "latest/stable")
    config      = optional(map(string), { database-name = "mongodb", extra-user-roles = "admin" })
    constraints = optional(string, "arch=amd64 spaces=clients")
    endpoint_bindings = optional(set(object({
      space    = string
      endpoint = optional(string)
      })), [
      {
        endpoint = "mongos"
        space    = "clients"
      },
    ])
    machines           = optional(set(string), [])
    revision           = optional(number, null)
    storage_directives = optional(map(string), {})
    units              = optional(number, 1)
  })
  default = {}
}

variable "s3_integrator" {
  description = "Optional S3 backup integrator configuration."
  type = object({
    base        = optional(string, "ubuntu@24.04")
    channel     = optional(string, "2/stable")
    config      = map(string)
    constraints = optional(string, "arch=amd64")
    machines    = optional(set(string), [])
    revision    = optional(number, null)
  })
  default = null

  validation {
    condition     = var.s3_integrator == null || length(var.s3_integrator.machines) <= 1
    error_message = "The backup integrator can be placed on at most one machine."
  }
}

variable "etcd" {
  description = "Charmed etcd configuration. It is deployed in a hardcoded 'mongodb-etcd' model using the etcd charm module."
  type = object({
    app_name          = optional(string, "etcd")
    channel           = optional(string, "3.6/stable")
    revision          = optional(number, null)
    base              = optional(string, "ubuntu@24.04")
    constraints       = optional(string, "arch=amd64")
    config            = optional(map(string), {})
    storage           = optional(map(string), {})
    units             = optional(number, 3)
    machines          = optional(set(string), null)
    endpoint_bindings = optional(map(string), {})
    expose            = optional(bool, false)
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
    app_name = optional(string, "opentelemetry-collector")
    base     = optional(string, "ubuntu@24.04")
    channel  = optional(string, "2/stable")
    config   = optional(map(string), {})
    revision = optional(number, null)
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
