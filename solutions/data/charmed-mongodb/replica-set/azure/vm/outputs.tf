# Copyright 2026 Canonical Ltd.
# See LICENSE file for licensing details.

output "components" {
  description = "Map of all components deployed by the solution."
  value = merge(module.mongodb_replica_set.components, {
    self_signed_certificates = juju_application.self_signed_certificates
    opentelemetry_collector  = juju_application.opentelemetry_collector
    cos                      = module.cos.components
  })
}

output "metadata" {
  description = "Metadata of the MongoDB replica-set deployment."
  value       = module.mongodb_replica_set.metadata
}

output "models" {
  description = "Map keyed by model UUID containing the components deployed in each model."
  value = merge(module.mongodb_replica_set.models, {
    (juju_model.mongodb.uuid) = {
      model_uuid = juju_model.mongodb.uuid
      components = merge(
        try(module.mongodb_replica_set.models[juju_model.mongodb.uuid].components, {}),
        {
          self_signed_certificates = juju_application.self_signed_certificates
          opentelemetry_collector  = juju_application.opentelemetry_collector
        }
      )
    }
    (juju_model.cos.uuid) = {
      model_uuid = juju_model.cos.uuid
      components = module.cos.components
    }
  })
}

output "offers" {
  description = "Map of all offers exposed by the MongoDB replica-set module."
  value       = module.mongodb_replica_set.offers
}
