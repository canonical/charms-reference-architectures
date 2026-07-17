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

resource "juju_model" "cos" {
  name       = var.cos.model
  credential = var.cos.credential
  cloud {
    name = var.cos.cloud
  }
}

module "cos" {
  source  = "git::https://github.com/canonical/observability-stack//terraform/cos-lite?ref=2.0a1"
  model   = var.cos.model
  channel = var.cos.channel

  depends_on = [juju_model.cos]
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

resource "juju_application" "etcd" {
  charm {
    name     = "charmed-etcd"
    channel  = var.etcd.channel
    revision = var.etcd.revision
    base     = var.etcd.base
  }

  name               = var.etcd.app_name
  config             = var.etcd.config
  constraints        = var.etcd.constraints
  model_uuid         = juju_model.mongodb.uuid
  storage_directives = var.etcd.storage_directives
  units              = var.etcd.units
}

resource "juju_application" "vault" {
  charm {
    name     = "vault"
    channel  = var.vault.channel
    revision = var.vault.revision
    base     = var.vault.base
  }

  name               = var.vault.app_name
  config             = var.vault.config
  constraints        = var.vault.constraints
  model_uuid         = juju_model.mongodb.uuid
  storage_directives = var.vault.storage_directives
  units              = var.vault.units
}

resource "juju_application" "opentelemetry_collector" {
  charm {
    name     = "opentelemetry-collector"
    channel  = var.opentelemetry_collector.channel
    revision = var.opentelemetry_collector.revision
    base     = var.opentelemetry_collector.base
  }

  name        = var.opentelemetry_collector.app_name
  config      = var.opentelemetry_collector.config
  constraints = var.opentelemetry_collector.constraints
  model_uuid  = juju_model.mongodb.uuid
  units       = 0
}

resource "juju_integration" "etcd_peer_certificates" {
  model_uuid = juju_model.mongodb.uuid

  application {
    name     = juju_application.etcd.name
    endpoint = "peer-certificates"
  }
  application {
    name     = juju_application.self_signed_certificates.name
    endpoint = "certificates"
  }
}

resource "juju_integration" "etcd_client_certificates" {
  model_uuid = juju_model.mongodb.uuid

  application {
    name     = juju_application.etcd.name
    endpoint = "client-certificates"
  }
  application {
    name     = juju_application.self_signed_certificates.name
    endpoint = "certificates"
  }
}

resource "juju_integration" "vault_certificates" {
  model_uuid = juju_model.mongodb.uuid

  application {
    name     = juju_application.vault.name
    endpoint = "certificates"
  }
  application {
    name     = juju_application.self_signed_certificates.name
    endpoint = "certificates"
  }
}

module "mongodb_replica_set" {
  # TODO: change this ref to 8/edge after DPE-10290-rs is merged.
  source = "git::https://github.com/canonical/mongodb-operator//terraform/product/replica_set?ref=DPE-10290-rs"

  mongodb = merge(var.mongodb, {
    model_uuid = juju_model.mongodb.uuid
    config = merge(var.mongodb.config, {
      "enable-encryption-at-rest" = "true"
    })
  })
  data_integrator = merge(var.data_integrator, {
    model_uuid = juju_model.mongodb.uuid
  })
  backups_integrator = var.backups_integrator == null ? null : merge(var.backups_integrator, {
    model_uuid = juju_model.mongodb.uuid
  })
  s3_access_key          = var.s3_access_key
  s3_secret_key          = var.s3_secret_key
  gcs_secret_key         = var.gcs_secret_key
  tls_client_private_key = var.tls_client_private_key
  tls_peer_private_key   = var.tls_peer_private_key

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
  etcd_integration = {
    kind     = "endpoint"
    name     = juju_application.etcd.name
    endpoint = "etcd-client"
  }
  vault_kv_integration = {
    kind     = "endpoint"
    name     = juju_application.vault.name
    endpoint = "vault-kv"
  }
  cos_agent_integration = {
    name     = juju_application.opentelemetry_collector.name
    endpoint = "cos-agent"
  }

  depends_on = [
    juju_integration.etcd_client_certificates,
    juju_integration.etcd_peer_certificates,
    juju_integration.vault_certificates,
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

output "applications" {
  description = "Applications deployed by the solution."
  value = merge(module.mongodb_replica_set.components, {
    etcd                     = juju_application.etcd.name
    opentelemetry_collector  = juju_application.opentelemetry_collector.name
    self_signed_certificates = juju_application.self_signed_certificates.name
    vault                    = juju_application.vault.name
  })
}
