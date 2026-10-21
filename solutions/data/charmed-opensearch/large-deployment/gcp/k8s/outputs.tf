# Copyright 2026 Canonical Ltd.
# See LICENSE file for licensing details.

output "app_names" {
  description = "Names of the applications deployed by the OpenSearch product module."
  value       = module.opensearch.app_names
}

output "cos" {
  description = "COS Lite model UUID and offer URLs. null without COS."
  value = local.cos_enabled ? {
    model_uuid = module.cos[0].model_uuid
    offers     = { for key, offer in module.cos[0].offers : key => offer.url }
  } : null
}

output "metadata" {
  description = "Metadata of the OpenSearch product deployment."
  value       = module.opensearch.metadata
}

output "models" {
  description = "Models by UUID, with the applications deployed in each."
  value = merge(
    {
      for name, model in juju_model.opensearch : model.uuid => {
        model_uuid = model.uuid
        components = merge(
          try(module.opensearch.models[model.uuid].components, {}),
          name == var.opensearch_model ? { traefik = juju_application.traefik } : {},
          local.cos_enabled ? { opentelemetry_collector = juju_application.opentelemetry_collector[name] } : {},
        )
      }
    },
    local.cos_enabled ? {
      (module.cos[0].model_uuid) = { model_uuid = module.cos[0].model_uuid, components = module.cos[0].components }
    } : {},
  )
}

output "offers" {
  description = "Map of all offers made by the OpenSearch product module."
  value       = module.opensearch.offers
}
