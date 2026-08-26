# Copyright 2026 Canonical Ltd.
# See LICENSE file for licensing details.

output "components" {
  description = "Map of all components deployed by the solution."
  sensitive   = true
  value = merge(module.mongodb_replica_set.components, {
    self_signed_certificates = module.self_signed_certificates
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
          self_signed_certificates = module.self_signed_certificates
          opentelemetry_collector  = juju_application.opentelemetry_collector
        }
      )
    }
    (module.cos.model_uuid) = {
      model_uuid = module.cos.model_uuid
      components = module.cos.components
    }
  })
}

output "offers" {
  description = "Map of all offers exposed by the solution."
  value       = module.mongodb_replica_set.offers
}
