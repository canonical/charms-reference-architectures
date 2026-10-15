# Copyright 2026 Canonical Ltd.
# See LICENSE file for licensing details.

variable "mongodb_model" {
  description = "Configuration for the Kubernetes model that hosts MongoDB."
  type = object({
    name       = optional(string, "mongodb")
    cloud      = optional(string, "k8s")
    credential = optional(string, "k8s")
  })
  default = {}
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

variable "mongodb" {
  description = "MongoDB replica-set application configuration."
  type = object({
    app_name    = optional(string, "mongodb-k8s")
    base        = optional(string, "ubuntu@24.04")
    channel     = optional(string, "8/stable")
    config      = optional(map(string), { role = "replication" })
    constraints = optional(string, "arch=amd64")
    expose = optional(list(object({
      cidrs     = optional(string)
      endpoints = optional(string)
    })), [])
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

variable "self_signed_certificates" {
  description = "Self-signed-certificates application configuration."
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

# Configuration variables

variable "s3_access_key" {
  description = "s3 access key. Supply through TF_VAR_s3_access_key at plan and apply. Warning: passing credentials through -var may expose them in shell history."
  type        = string
  sensitive   = true
  ephemeral   = true
  default     = null
}

variable "s3_secret_key" {
  description = "s3 secret key. Supply through TF_VAR_s3_secret_key at plan and apply. Warning: passing credentials through -var may expose them in shell history."
  type        = string
  sensitive   = true
  ephemeral   = true
  default     = null
}

variable "s3_secret_version" {
  description = "0 creates no secret. 1 creates it. Increment to rotate. Ignored when s3_secret_uri is set."
  type        = number
  default     = 0

  validation {
    condition     = var.s3_secret_uri != null || var.s3_secret_version == 0 || var.s3_integrator != null
    error_message = "s3_secret_version requires s3_integrator unless s3_secret_uri is set."
  }
}

variable "s3_secret_uri" {
  description = "URI of an existing Juju secret in the consuming application's model. Takes priority over credentials and s3_secret_version."
  type        = string
  default     = null

  validation {
    condition     = var.s3_secret_uri == null || startswith(coalesce(var.s3_secret_uri, "-"), "secret:")
    error_message = "s3_secret_uri must be a Juju secret URI starting with 'secret:'."
  }
}

variable "tls_client_private_key" {
  description = "tls client private key. Supply through TF_VAR_tls_client_private_key at plan and apply. Warning: passing credentials through -var may expose them in shell history."
  type        = string
  sensitive   = true
  ephemeral   = true
  default     = null
}

variable "tls_client_private_key_version" {
  description = "0 creates no secret. 1 creates it. Increment to rotate. Ignored when tls_client_private_key_secret_uri is set."
  type        = number
  default     = 0
}

variable "tls_client_private_key_secret_uri" {
  description = "URI of an existing Juju secret in the consuming application's model. Takes priority over credentials and tls_client_private_key_version."
  type        = string
  default     = null

  validation {
    condition     = var.tls_client_private_key_secret_uri == null || startswith(coalesce(var.tls_client_private_key_secret_uri, "-"), "secret:")
    error_message = "tls_client_private_key_secret_uri must be a Juju secret URI starting with 'secret:'."
  }
}

variable "tls_peer_private_key" {
  description = "tls peer private key. Supply through TF_VAR_tls_peer_private_key at plan and apply. Warning: passing credentials through -var may expose them in shell history."
  type        = string
  sensitive   = true
  ephemeral   = true
  default     = null
}

variable "tls_peer_private_key_version" {
  description = "0 creates no secret. 1 creates it. Increment to rotate. Ignored when tls_peer_private_key_secret_uri is set."
  type        = number
  default     = 0
}

variable "tls_peer_private_key_secret_uri" {
  description = "URI of an existing Juju secret in the consuming application's model. Takes priority over credentials and tls_peer_private_key_version."
  type        = string
  default     = null

  validation {
    condition     = var.tls_peer_private_key_secret_uri == null || startswith(coalesce(var.tls_peer_private_key_secret_uri, "-"), "secret:")
    error_message = "tls_peer_private_key_secret_uri must be a Juju secret URI starting with 'secret:'."
  }
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

variable "logging_config" {
  description = "Logging configuration used by the MongoDB replica-set module."
  type        = string
  default     = "<root>=INFO"
}
