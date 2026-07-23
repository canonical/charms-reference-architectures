# Copyright 2026 Canonical Ltd.
# See LICENSE file for licensing details.

output "components" {
  description = "Map of all components deployed by the solution."
  value = merge(module.mongodb_sharded_cluster.components, {
    self_signed_certificates = juju_application.self_signed_certificates
    etcd                     = juju_application.etcd
  })
}

output "metadata" {
  description = "Metadata of the MongoDB sharded-cluster deployment."
  value       = module.mongodb_sharded_cluster.metadata
}

output "models" {
  description = "Map keyed by model UUID containing the components deployed in each model."
  value = merge(module.mongodb_sharded_cluster.models, {
    (juju_model.config_server.uuid) = {
      model_uuid = juju_model.config_server.uuid
      components = merge(
        try(module.mongodb_sharded_cluster.models[juju_model.config_server.uuid].components, {}),
        {
          self_signed_certificates = juju_application.self_signed_certificates
          etcd                     = juju_application.etcd
        }
      )
    }
  })
}

output "offers" {
  description = "Map of offers exposed by the solution."
  value = merge(module.mongodb_sharded_cluster.offers, {
    certificates = juju_offer.certificates.url
    etcd         = juju_offer.etcd.url
  })
}
