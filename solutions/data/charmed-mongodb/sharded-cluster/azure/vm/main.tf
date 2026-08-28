# Copyright 2026 Canonical Ltd.
# See LICENSE file for licensing details.

# Data source to reference Azure infrastructure created by clouds/azure module
data "terraform_remote_state" "infra_state" {
  backend = "azurerm"
  config  = var.remote_state
}

# Juju credentials are provided through the provider environment variables.
provider "juju" {}

# MongoDB models
resource "juju_model" "config_server" {
  name = var.models.config_server
  cloud {
    name = "azure"
  }
  config = {
    "resource-group-name" = data.terraform_remote_state.infra_state.outputs.infrastructure.resource_group_name
    "network"             = data.terraform_remote_state.infra_state.outputs.infrastructure.vnet_name
  }
}

# Dynamic shard models - creates one model per shard using centralized model names
resource "juju_model" "shards" {
  for_each = {
    for i, shard in var.shards : i => {
      name         = var.models.shards[i]
      shard_config = shard
    }
  }

  name = each.value.name
  cloud {
    name = "azure"
  }
  config = {
    "resource-group-name" = data.terraform_remote_state.infra_state.outputs.infrastructure.resource_group_name
    "network"             = data.terraform_remote_state.infra_state.outputs.infrastructure.vnet_name
  }
}

# Etcd model (hardcoded name)
resource "juju_model" "etcd" {
  name = "mongodb-etcd"
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

# Etcd deployment using the charm module (etcd + self-signed certificates only)
module "charmed_etcd" {
  source = "git::https://github.com/canonical/charmed-etcd-operator//terraform/charm?ref=3.6/edge"

  app_name          = var.etcd.app_name
  base              = var.etcd.base
  channel           = var.etcd.channel
  config            = var.etcd.config
  constraints       = var.etcd.constraints
  endpoint_bindings = var.etcd.endpoint_bindings
  expose            = var.etcd.expose
  machines          = var.etcd.machines
  model_uuid        = juju_model.etcd.uuid
  revision          = var.etcd.revision
  storage           = var.etcd.storage
  units             = var.etcd.units

  tls = true
  self-signed-certificates = {
    channel = "1/stable"
    config  = { "ca-common-name" = "Etcd CA" }
  }

  depends_on = [juju_model.etcd]
}

# Etcd offer for config server and shards integration (rollingops)
resource "juju_offer" "etcd" {
  application_name = module.charmed_etcd.app_names.etcd
  endpoints        = ["etcd-client"]
  model_uuid       = juju_model.etcd.uuid
}

# Self-signed certificates for MongoDB (in config-server model)
module "self_signed_certificates" {
  source = "git::https://github.com/canonical/self-signed-certificates-operator//terraform?ref=main"

  model_uuid  = juju_model.config_server.uuid
  app_name    = var.self_signed_certificates.app_name
  base        = var.self_signed_certificates.base
  channel     = var.self_signed_certificates.channel
  revision    = var.self_signed_certificates.revision
  config      = var.self_signed_certificates.config
  constraints = var.self_signed_certificates.constraints
  units       = var.self_signed_certificates.units
}

# Certificates offer meant to be used by the shards
resource "juju_offer" "certificates" {
  application_name = module.self_signed_certificates.app_name
  endpoints        = ["certificates"]
  model_uuid       = juju_model.config_server.uuid
}

# OpenTelemetry Collector applications (always deployed)
resource "juju_application" "opentelemetry_collector_config" {
  charm {
    name     = "opentelemetry-collector"
    channel  = var.opentelemetry_collector.channel
    revision = var.opentelemetry_collector.revision
    base     = var.opentelemetry_collector.base
  }

  name       = "${var.opentelemetry_collector.app_name}-config"
  config     = var.opentelemetry_collector.config
  model_uuid = juju_model.config_server.uuid
}

resource "juju_application" "opentelemetry_collector_shards" {
  for_each = { for i, shard in var.shards : i => shard }

  charm {
    name     = "opentelemetry-collector"
    channel  = var.opentelemetry_collector.channel
    revision = var.opentelemetry_collector.revision
    base     = var.opentelemetry_collector.base
  }

  name       = "${var.opentelemetry_collector.app_name}-shard${each.key + 1}"
  config     = var.opentelemetry_collector.config
  model_uuid = juju_model.shards[each.key].uuid
}

# COS integrations for OpenTelemetry Collectors (always deployed)
resource "juju_integration" "opentelemetry_collector_config_prometheus" {
  model_uuid = juju_model.config_server.uuid
  application {
    name     = juju_application.opentelemetry_collector_config.name
    endpoint = "send-remote-write"
  }
  application {
    offer_url = module.cos.offers.prometheus_receive_remote_write.url
  }
}

resource "juju_integration" "opentelemetry_collector_config_loki" {
  model_uuid = juju_model.config_server.uuid
  application {
    name     = juju_application.opentelemetry_collector_config.name
    endpoint = "send-loki-logs"
  }
  application {
    offer_url = module.cos.offers.loki_logging.url
  }
}

resource "juju_integration" "opentelemetry_collector_config_dashboards" {
  model_uuid = juju_model.config_server.uuid
  application {
    name     = juju_application.opentelemetry_collector_config.name
    endpoint = "grafana-dashboards-provider"
  }
  application {
    offer_url = module.cos.offers.grafana_dashboards.url
  }
}

resource "juju_integration" "opentelemetry_collector_shards_prometheus" {
  for_each = { for i, shard in var.shards : i => shard }

  model_uuid = juju_model.shards[each.key].uuid
  application {
    name     = juju_application.opentelemetry_collector_shards[each.key].name
    endpoint = "send-remote-write"
  }
  application {
    offer_url = module.cos.offers.prometheus_receive_remote_write.url
  }
}

resource "juju_integration" "opentelemetry_collector_shards_loki" {
  for_each = { for i, shard in var.shards : i => shard }

  model_uuid = juju_model.shards[each.key].uuid
  application {
    name     = juju_application.opentelemetry_collector_shards[each.key].name
    endpoint = "send-loki-logs"
  }
  application {
    offer_url = module.cos.offers.loki_logging.url
  }
}

resource "juju_integration" "opentelemetry_collector_shards_dashboards" {
  for_each = { for i, shard in var.shards : i => shard }

  model_uuid = juju_model.shards[each.key].uuid
  application {
    name     = juju_application.opentelemetry_collector_shards[each.key].name
    endpoint = "grafana-dashboards-provider"
  }
  application {
    offer_url = module.cos.offers.grafana_dashboards.url
  }
}

# MongoDB sharded cluster
module "mongodb_sharded_cluster" {
  source = "git::https://github.com/canonical/mongodb-operator//terraform/product/sharded_cluster?ref=8/edge"

  config_server = merge(var.config_server, {
    model_uuid = juju_model.config_server.uuid
  })
  mongos = var.mongos
  shards = [
    for i, shard in var.shards : merge(shard, {
      model_uuid = juju_model.shards[i].uuid
    })
  ]
  data_integrator = merge(var.data_integrator, {
    model_uuid = juju_model.config_server.uuid
  })
  client_certificates_integration = {
    name       = module.self_signed_certificates.app_name
    endpoint   = "certificates"
    model_uuid = juju_model.config_server.uuid
    url        = juju_offer.certificates.url
  }
  peer_certificates_integration = {
    name       = module.self_signed_certificates.app_name
    endpoint   = "certificates"
    model_uuid = juju_model.config_server.uuid
    url        = juju_offer.certificates.url
  }
  etcd_integration = {
    name       = module.charmed_etcd.app_names.etcd
    endpoint   = "etcd-client"
    model_uuid = juju_model.etcd.uuid
    url        = juju_offer.etcd.url
  }
  cos_agent_integrations = merge(
    {
      "config-server" = {
        name     = juju_application.opentelemetry_collector_config.name
        endpoint = "cos-agent"
      }
    },
    {
      for i, shard in var.shards : shard.app_name => {
        name     = juju_application.opentelemetry_collector_shards[i].name
        endpoint = "cos-agent"
      }
    }
  )
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

  tls_client_private_key = var.tls_client_private_key
  tls_peer_private_key   = var.tls_peer_private_key
  logging_config         = var.logging_config

  depends_on = [
    module.self_signed_certificates,
    module.charmed_etcd
  ]
}
