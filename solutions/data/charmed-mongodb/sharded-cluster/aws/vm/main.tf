# Copyright 2026 Canonical Ltd.
# See LICENSE file for licensing details.

provider "juju" {}

# MongoDB models
resource "juju_model" "config_server" {
  name       = var.models.config_server
  credential = var.model_config.credential
  cloud {
    name = var.model_config.cloud
  }
  config = var.vpc_id == null ? {} : {
    vpc-id = var.vpc_id
  }
}

# Dynamic shard models - creates one model per shard
resource "juju_model" "shards" {
  for_each = {
    for i, shard in var.shards : i => {
      name       = shard.model_name != null ? shard.model_name : "mongodb-shard-${i + 1}"
      shard_config = shard
    }
  }
  
  name       = each.value.name
  credential = var.model_config.credential
  cloud {
    name = var.model_config.cloud
  }
  config = var.vpc_id == null ? {} : {
    vpc-id = var.vpc_id
  }
}

# Etcd model (hardcoded name)
resource "juju_model" "etcd" {
  name       = "mongodb-etcd"
  credential = var.model_config.credential
  cloud {
    name = var.model_config.cloud
  }
  config = var.vpc_id == null ? {} : {
    vpc-id = var.vpc_id
  }
}

# COS (Charmed Observability Stack)
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

# Etcd deployment with simplified configuration
module "charmed_etcd" {
  source = "git::https://github.com/canonical/charmed-etcd-operator//terraform/product?ref=3.6/edge"

  etcd = merge(var.etcd, {
    model = juju_model.etcd.name
  })
  
  # Simplified self-signed certificates for etcd only
  self-signed-certificates = {
    channel = "1/stable"
    config  = { "ca-common-name" = "Etcd CA" }
  }
  
  depends_on = [juju_model.etcd]
}

# Etcd offer for MongoDB integration
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

# MongoDB certificates offer
resource "juju_offer" "certificates" {
  application_name = module.self_signed_certificates.app_name
  endpoints        = ["certificates"]
  model_uuid       = juju_model.config_server.uuid
}

# OpenTelemetry Collector applications (when enabled)
resource "juju_application" "opentelemetry_collector_config" {
  count = var.opentelemetry_collector.enabled ? 1 : 0
  
  charm {
    name     = "opentelemetry-collector"
    channel  = var.opentelemetry_collector.channel
    revision = var.opentelemetry_collector.revision
    base     = var.opentelemetry_collector.base
  }

  name        = "${var.opentelemetry_collector.app_name}-config"
  config      = var.opentelemetry_collector.config
  constraints = var.opentelemetry_collector.constraints
  model_uuid  = juju_model.config_server.uuid
}

resource "juju_application" "opentelemetry_collector_shards" {
  for_each = var.opentelemetry_collector.enabled ? { for i, shard in var.shards : i => shard } : {}
  
  charm {
    name     = "opentelemetry-collector"
    channel  = var.opentelemetry_collector.channel
    revision = var.opentelemetry_collector.revision
    base     = var.opentelemetry_collector.base
  }

  name        = "${var.opentelemetry_collector.app_name}-shard-${each.key + 1}"
  config      = var.opentelemetry_collector.config
  constraints = var.opentelemetry_collector.constraints
  model_uuid  = juju_model.shards[each.key].uuid
}

# COS integrations for OpenTelemetry Collectors
resource "juju_integration" "opentelemetry_collector_config_prometheus" {
  count = var.opentelemetry_collector.enabled ? 1 : 0
  
  model_uuid = juju_model.config_server.uuid
  application {
    name     = juju_application.opentelemetry_collector_config[0].name
    endpoint = "send-remote-write"
  }
  application {
    offer_url = module.cos.offers.prometheus_receive_remote_write.url
  }
}

resource "juju_integration" "opentelemetry_collector_config_loki" {
  count = var.opentelemetry_collector.enabled ? 1 : 0
  
  model_uuid = juju_model.config_server.uuid
  application {
    name     = juju_application.opentelemetry_collector_config[0].name
    endpoint = "send-loki-logs"
  }
  application {
    offer_url = module.cos.offers.loki_logging.url
  }
}

resource "juju_integration" "opentelemetry_collector_config_dashboards" {
  count = var.opentelemetry_collector.enabled ? 1 : 0
  
  model_uuid = juju_model.config_server.uuid
  application {
    name     = juju_application.opentelemetry_collector_config[0].name
    endpoint = "grafana-dashboards-provider"
  }
  application {
    offer_url = module.cos.offers.grafana_dashboards.url
  }
}

resource "juju_integration" "opentelemetry_collector_shards_prometheus" {
  for_each = var.opentelemetry_collector.enabled ? { for i, shard in var.shards : i => shard } : {}
  
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
  for_each = var.opentelemetry_collector.enabled ? { for i, shard in var.shards : i => shard } : {}
  
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
  for_each = var.opentelemetry_collector.enabled ? { for i, shard in var.shards : i => shard } : {}
  
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
  backups_integrator = var.s3_integrator == null ? null : merge(var.s3_integrator, {
    storage_type = "s3"
    model_uuid   = juju_model.config_server.uuid
  })

  # MongoDB TLS certificates integration (from config-server model)
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
  
  # Etcd integration (from separate etcd model)
  etcd_integration = {
    name       = module.charmed_etcd.app_names.etcd
    endpoint   = "etcd-client"
    model_uuid = juju_model.etcd.uuid
    url        = juju_offer.etcd.url
  }
  
  # COS integration via OpenTelemetry Collector applications
  cos_agent_integrations = var.opentelemetry_collector.enabled ? merge(
    {
      "config-server" = {
        name     = juju_application.opentelemetry_collector_config[0].name
        endpoint = "cos-agent"
      }
    },
    {
      for i, shard in var.shards : shard.app_name => {
        name     = juju_application.opentelemetry_collector_shards[i].name
        endpoint = "cos-agent"
      }
    }
  ) : {}
  
  # Optional LDAP integrations
  ldap_integration = var.ldap_integration == null ? null : {
    kind = "offer"
    url  = var.ldap_integration.url
  }
  ldap_certificate_transfer_integration = var.ldap_certificate_transfer_integration == null ? null : {
    kind = "offer"
    url  = var.ldap_certificate_transfer_integration.url
  }
  
  # Optional Vault integration
  vault_kv_integration = var.vault_kv_integration == null ? null : {
    kind = "offer"
    url  = var.vault_kv_integration.url
  }

  s3_access_key          = var.s3_access_key
  s3_secret_key          = var.s3_secret_key
  tls_client_private_key = var.tls_client_private_key
  tls_peer_private_key   = var.tls_peer_private_key
  logging_config         = var.logging_config

  depends_on = [
    module.self_signed_certificates,
    module.charmed_etcd
  ]
}
