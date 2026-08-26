# Copyright 2026 Canonical Ltd.
# See LICENSE file for licensing details.

output "components" {
  description = "Map of all components deployed by the solution."
  sensitive   = true
  value = merge(
    module.mongodb_sharded_cluster.components,
    {
      self_signed_certificates = module.self_signed_certificates
      cos                      = module.cos.components
    }
  )
}

output "metadata" {
  description = "Metadata of the MongoDB sharded-cluster deployment."
  value       = module.mongodb_sharded_cluster.metadata
}

output "models" {
  description = "Map keyed by model UUID containing the components deployed in each model."
  sensitive   = true
  value = merge(
    module.mongodb_sharded_cluster.models,
    {
      (juju_model.config_server.uuid) = {
        model_uuid = juju_model.config_server.uuid
        components = merge(
          try(module.mongodb_sharded_cluster.models[juju_model.config_server.uuid].components, {}),
          {
            self_signed_certificates = module.self_signed_certificates
          }
        )
      }
    },
    # Add all shard models dynamically
    {
      for i, shard_model in juju_model.shards : shard_model.uuid => {
        model_uuid = shard_model.uuid
        components = try(module.mongodb_sharded_cluster.models[shard_model.uuid].components, {})
      }
    },
    {
      (module.cos.model_uuid) = {
        model_uuid = module.cos.model_uuid
        components = module.cos.components
      }
    }
  )
}

output "offers" {
  description = "Map of offers exposed by the solution."
  value = merge(
    module.mongodb_sharded_cluster.offers,
    module.cos.offers,
    {
      mongodb_certificates = juju_offer.certificates.url
    }
  )
}

output "shard_models" {
  description = "Map of shard models created, keyed by shard index."
  value = {
    for i, shard_model in juju_model.shards : i => {
      name       = shard_model.name
      uuid       = shard_model.uuid
      shard_name = var.shards[i].app_name
    }
  }
}
