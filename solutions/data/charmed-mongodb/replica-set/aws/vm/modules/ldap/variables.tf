# Copyright 2026 Canonical Ltd.
# See LICENSE file for licensing details.

variable "model" {
  description = "Name of the Kubernetes model used for LDAP."
  type        = string
  default     = "ldap"
}

variable "cloud" {
  description = "Name of the Kubernetes cloud."
  type        = string
  default     = "k8s"
}

variable "credential" {
  description = "Name of the Kubernetes cloud credential."
  type        = string
  default     = "k8s"
}

variable "self_signed_certificates" {
  description = "Self-signed certificates application configuration."
  type = object({
    app_name    = optional(string, "self-signed-certificates")
    base        = optional(string, "ubuntu@24.04")
    channel     = optional(string, "1/stable")
    revision    = optional(number, null)
    config      = optional(map(string), {})
    constraints = optional(string, "arch=amd64")
    units       = optional(number, 1)
  })
  default = {}
}

variable "glauth" {
  description = "GLAuth application configuration."
  type = object({
    app_name    = optional(string, "glauth-k8s")
    base        = optional(string, "ubuntu@22.04")
    channel     = optional(string, "latest/stable")
    revision    = optional(number, null)
    config      = optional(map(string), {})
    constraints = optional(string, "")
    units       = optional(number, 1)
  })
  default = {}
}

variable "glauth_utils" {
  description = "GLAuth Utils application configuration."
  type = object({
    app_name = optional(string, "glauth-utils")
    channel  = optional(string, "latest/edge")
    revision = optional(number, null)
    config   = optional(map(string), {})
  })
  default = {}
}

variable "traefik" {
  description = "Traefik application configuration."
  type = object({
    app_name           = optional(string, "traefik-k8s")
    base               = optional(string, null)
    channel            = optional(string, "latest/stable")
    revision           = optional(number, null)
    config             = optional(map(string), {})
    constraints        = optional(string, "arch=amd64")
    expose             = optional(bool, false)
    resources          = optional(map(string), {})
    storage_directives = optional(map(string), {})
    units              = optional(number, 1)
  })
  default = {}
}

variable "postgresql" {
  description = "PostgreSQL application configuration."
  type = object({
    app_name           = optional(string, "postgresql-k8s")
    base               = optional(string, "ubuntu@24.04")
    channel            = optional(string, "16/stable")
    revision           = optional(number, null)
    config             = optional(map(string), {})
    constraints        = optional(string, "arch=amd64")
    resources          = optional(map(string), {})
    storage_directives = optional(map(string), {})
    units              = optional(number, 1)
  })
  default = {}
}
