# Copyright 2026 Canonical Ltd.
# See LICENSE file for licensing details.

provider "juju" {}

resource "juju_model" "config_server" {
  name = var.models.config_server
  cloud {
    name = "aws"
  }
}

resource "juju_model" "shard_one" {
  name = var.models.shard_one
  cloud {
    name = "aws"
  }
}

resource "juju_model" "shard_two" {
  name = var.models.shard_two
  cloud {
    name = "aws"
  }
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
  model_uuid  = juju_model.config_server.uuid
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
  model_uuid         = juju_model.config_server.uuid
  storage_directives = var.etcd.storage_directives
  units              = var.etcd.units
}

resource "juju_integration" "etcd_client_certificates" {
  model_uuid = juju_model.config_server.uuid

  application {
    name     = juju_application.etcd.name
    endpoint = "client-certificates"
  }
  application {
    name     = juju_application.self_signed_certificates.name
    endpoint = "certificates"
  }
}

resource "juju_offer" "certificates" {
  application_name = juju_application.self_signed_certificates.name
  endpoints        = ["certificates"]
  model_uuid       = juju_model.config_server.uuid
}

resource "juju_offer" "etcd" {
  application_name = juju_application.etcd.name
  endpoints        = ["etcd-client"]
  model_uuid       = juju_model.config_server.uuid
}

module "mongodb_sharded_cluster" {
  source = "git::https://github.com/canonical/mongodb-operator//terraform/product/sharded_cluster?ref=8/edge"

  config_server = merge(var.config_server, {
    model_uuid = juju_model.config_server.uuid
  })
  mongos = var.mongos
  shards = [
    for index, shard in var.shards : merge(shard, {
      model_uuid = index == 0 ? juju_model.shard_one.uuid : juju_model.shard_two.uuid
    })
  ]
  data_integrator = merge(var.data_integrator, {
    model_uuid = juju_model.config_server.uuid
  })
  backups_integrator = var.s3_integrator == null ? null : merge(var.s3_integrator, {
    storage_type = "s3"
    model_uuid   = juju_model.config_server.uuid
  })

  client_certificates_integration = {
    name       = juju_application.self_signed_certificates.name
    endpoint   = "certificates"
    model_uuid = juju_model.config_server.uuid
    url        = juju_offer.certificates.url
  }
  peer_certificates_integration = {
    name       = juju_application.self_signed_certificates.name
    endpoint   = "certificates"
    model_uuid = juju_model.config_server.uuid
    url        = juju_offer.certificates.url
  }
  etcd_integration = {
    name       = juju_application.etcd.name
    endpoint   = "etcd-client"
    model_uuid = juju_model.config_server.uuid
    url        = juju_offer.etcd.url
  }

  s3_access_key          = var.s3_access_key
  s3_secret_key          = var.s3_secret_key
  tls_client_private_key = var.tls_client_private_key
  tls_peer_private_key   = var.tls_peer_private_key
  logging_config         = var.logging_config

  depends_on = [juju_integration.etcd_client_certificates]
}
