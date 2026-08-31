# Copyright 2026 Canonical Ltd.
# See LICENSE file for licensing details.

# Data source to reference Azure infrastructure created by clouds/azure module
data "terraform_remote_state" "infra_state" {
  backend = "azurerm"
  config  = var.remote-state
}

# Juju credentials are provided through the provider environment variables.
provider "juju" {}

resource "juju_model" "mongodb" {
  name = var.mongodb_model
  cloud {
    name = "azure"
  }
  config = {
    "resource-group-name" = data.terraform_remote_state.infra_state.outputs.infrastructure.resource_group_name
    "network"             = data.terraform_remote_state.infra_state.outputs.infrastructure.vnet_name
  }
}


module "cos" {
  source = "git::https://github.com/canonical/observability-stack//terraform/cos-lite?ref=tf-cos-lite-3.0.2"
  model = {
    name       = var.cos.model_name
    credential = var.cos.credential
    cloud = {
      name = var.cos.cloud
    }
  }
  risk = var.cos.risk
  grafana = {
    storage_directives = var.cos.grafana_storage_directives
  }
  loki = {
    storage_directives = var.cos.loki_storage_directives
  }
  prometheus = {
    storage_directives = var.cos.prometheus_storage_directives
  }
}

module "self_signed_certificates" {
  source = "git::https://github.com/canonical/self-signed-certificates-operator//terraform?ref=main"

  model_uuid  = juju_model.mongodb.uuid
  app_name    = var.self_signed_certificates.app_name
  base        = var.self_signed_certificates.base
  channel     = var.self_signed_certificates.channel
  revision    = var.self_signed_certificates.revision
  config      = var.self_signed_certificates.config
  constraints = var.self_signed_certificates.constraints
  units       = var.self_signed_certificates.units
}

resource "juju_application" "opentelemetry_collector" {
  charm {
    name     = "opentelemetry-collector"
    channel  = var.opentelemetry_collector.channel
    revision = var.opentelemetry_collector.revision
    base     = var.opentelemetry_collector.base
  }

  name       = var.opentelemetry_collector.app_name
  config     = var.opentelemetry_collector.config
  model_uuid = juju_model.mongodb.uuid
}

module "mongodb_replica_set" {
  source = "git::https://github.com/canonical/mongodb-operator//terraform/product/replica_set?ref=8/edge"

  mongodb = merge(var.mongodb, {
    model_uuid = juju_model.mongodb.uuid
  })
  data_integrator = merge(var.data_integrator, {
    model_uuid = juju_model.mongodb.uuid
  })
  backups_integrator = var.s3_integrator == null ? null : {
    config       = var.s3_integrator.config
    channel      = var.s3_integrator.channel
    base         = var.s3_integrator.base
    revision     = var.s3_integrator.revision
    constraints  = var.s3_integrator.constraints
    machines     = var.s3_integrator.machines
    model_uuid   = juju_model.mongodb.uuid
    storage_type = "s3"
  }
  s3_access_key          = var.s3_access_key
  s3_secret_key          = var.s3_secret_key
  tls_client_private_key = var.tls_client_private_key
  tls_peer_private_key   = var.tls_peer_private_key
  logging_config         = var.logging_config

  client_certificates_integration = {
    kind     = "endpoint"
    name     = module.self_signed_certificates.app_name
    endpoint = module.self_signed_certificates.provides["certificates"]
  }
  peer_certificates_integration = {
    kind     = "endpoint"
    name     = module.self_signed_certificates.app_name
    endpoint = module.self_signed_certificates.provides["certificates"]
  }
  cos_agent_integration = {
    name     = juju_application.opentelemetry_collector.name
    endpoint = "cos-agent"
  }
  ldap_integration = var.ldap_integration == null ? null : {
    kind = "offer"
    url  = var.ldap_integration.url
  }
  ldap_certificate_transfer_integration = var.ldap_certificate_transfer_integration == null ? null : {
    kind = "offer"
    url  = var.ldap_certificate_transfer_integration.url
  }
  vault_kv_integration = var.vault_kv_integration == null ? null : {
    kind = "offer"
    url  = var.vault_kv_integration.url
  }

  depends_on = [
    juju_model.mongodb,
  ]
}

resource "juju_integration" "opentelemetry_collector_prometheus" {
  model_uuid = juju_model.mongodb.uuid
  application {
    name     = juju_application.opentelemetry_collector.name
    endpoint = "send-remote-write"
  }
  application {
    offer_url = module.cos.offers.prometheus_receive_remote_write.url
  }
}

resource "juju_integration" "opentelemetry_collector_loki" {
  model_uuid = juju_model.mongodb.uuid
  application {
    name     = juju_application.opentelemetry_collector.name
    endpoint = "send-loki-logs"
  }
  application {
    offer_url = module.cos.offers.loki_logging.url
  }
}

resource "juju_integration" "opentelemetry_collector_dashboards" {
  model_uuid = juju_model.mongodb.uuid
  application {
    name     = juju_application.opentelemetry_collector.name
    endpoint = "grafana-dashboards-provider"
  }
  application {
    offer_url = module.cos.offers.grafana_dashboards.url
  }
}
