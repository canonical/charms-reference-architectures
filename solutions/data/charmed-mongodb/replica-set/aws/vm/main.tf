# Copyright 2026 Canonical Ltd.
# See LICENSE file for licensing details.

# Juju credentials are provided through the provider environment variables.
provider "juju" {}

resource "juju_model" "mongodb" {
  name = var.mongodb_model
  cloud {
    name = "aws"
  }
}

module "cos" {
  source = "git::https://github.com/canonical/observability-stack//terraform/cos-lite?ref=tf-cos-lite-3.0.2"
  model = {
    name       = var.cos.model
    credential = var.cos.credential
    cloud = {
      name = var.cos.cloud
    }
  }
  risk = var.cos.risk
}

resource "juju_application" "self_signed_certificates" {
  charm {
    name     = "self-signed-certificates"
    channel  = var.self_signed_certificates.channel
    revision = var.self_signed_certificates.revision
    base     = var.self_signed_certificates.base
  }

  name        = var.self_signed_certificates.app_name
  config      = var.self_signed_certificates.config
  constraints = var.self_signed_certificates.constraints
  model_uuid  = juju_model.mongodb.uuid
  units       = 1
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
    name     = juju_application.self_signed_certificates.name
    endpoint = "certificates"
  }
  peer_certificates_integration = {
    kind     = "endpoint"
    name     = juju_application.self_signed_certificates.name
    endpoint = "certificates"
  }
  cos_agent_integration = {
    name     = juju_application.opentelemetry_collector.name
    endpoint = "cos-agent"
  }
  vault_kv_integration = var.vault_kv_integration

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
