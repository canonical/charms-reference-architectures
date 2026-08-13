# Copyright 2026 Canonical Ltd.
# See LICENSE file for licensing details.

resource "juju_model" "ldap" {
  name       = var.model
  credential = var.credential

  cloud {
    name = var.cloud
  }
}

module "self_signed_certificates" {
  source = "git::https://github.com/canonical/self-signed-certificates-operator//terraform?ref=main"

  model_uuid  = juju_model.ldap.uuid
  app_name    = var.self_signed_certificates.app_name
  base        = var.self_signed_certificates.base
  channel     = var.self_signed_certificates.channel
  revision    = var.self_signed_certificates.revision
  config      = var.self_signed_certificates.config
  constraints = var.self_signed_certificates.constraints
  units       = var.self_signed_certificates.units
}

module "glauth" {
  source = "git::https://github.com/canonical/glauth-k8s-operator//terraform?ref=main"

  model_uuid  = juju_model.ldap.uuid
  app_name    = var.glauth.app_name
  base        = var.glauth.base
  channel     = var.glauth.channel
  revision    = var.glauth.revision
  config      = var.glauth.config
  constraints = var.glauth.constraints
  units       = var.glauth.units
}

resource "juju_application" "glauth_utils" {
  charm {
    name     = "glauth-utils"
    channel  = var.glauth_utils.channel
    revision = var.glauth_utils.revision
  }
  name       = var.glauth_utils.app_name
  config     = var.glauth_utils.config
  model_uuid = juju_model.ldap.uuid
  trust      = true
  units      = 1
}

module "traefik" {
  source = "git::https://github.com/canonical/traefik-k8s-operator//terraform?ref=main"

  model_uuid         = juju_model.ldap.uuid
  app_name           = var.traefik.app_name
  base               = var.traefik.base
  channel            = var.traefik.channel
  revision           = var.traefik.revision
  config             = var.traefik.config
  constraints        = var.traefik.constraints
  expose             = var.traefik.expose
  resources          = var.traefik.resources
  storage_directives = var.traefik.storage_directives
  units              = var.traefik.units
}

module "postgresql" {
  source = "git::https://github.com/canonical/postgresql-k8s-operator//terraform?ref=16/edge"

  juju_model         = juju_model.ldap.uuid
  app_name           = var.postgresql.app_name
  base               = var.postgresql.base
  channel            = var.postgresql.channel
  revision           = var.postgresql.revision
  config             = var.postgresql.config
  constraints        = var.postgresql.constraints
  resources          = var.postgresql.resources
  storage_directives = var.postgresql.storage_directives
  units              = var.postgresql.units
}

resource "juju_integration" "glauth_ingress" {
  model_uuid = juju_model.ldap.uuid
  application {
    name     = module.glauth.app_name
    endpoint = module.glauth.requires["ldaps-ingress"]
  }
  application {
    name     = module.traefik.app_name
    endpoint = module.traefik.provides["ingress_per_unit"]
  }
}

resource "juju_integration" "glauth_database" {
  model_uuid = juju_model.ldap.uuid
  application {
    name     = module.glauth.app_name
    endpoint = "pg-database"
  }
  application {
    name     = module.postgresql.application_name
    endpoint = module.postgresql.provides["database"]
  }
}

resource "juju_integration" "glauth_certificates" {
  model_uuid = juju_model.ldap.uuid
  application {
    name     = module.glauth.app_name
    endpoint = module.glauth.requires["certificates"]
  }
  application {
    name     = module.self_signed_certificates.app_name
    endpoint = module.self_signed_certificates.provides["certificates"]
  }
}

resource "juju_integration" "glauth_utils" {
  model_uuid = juju_model.ldap.uuid
  application {
    name     = module.glauth.app_name
    endpoint = module.glauth.provides["glauth-auxiliary"]
  }
  application {
    name     = juju_application.glauth_utils.name
    endpoint = "glauth-auxiliary"
  }
}

resource "juju_offer" "ldap" {
  application_name = module.glauth.app_name
  endpoints        = [module.glauth.provides["ldap"]]
  model_uuid       = juju_model.ldap.uuid
}

resource "juju_offer" "send_ca_cert" {
  application_name = module.glauth.app_name
  endpoints        = [module.glauth.provides["send-ca-cert"]]
  model_uuid       = juju_model.ldap.uuid
}
