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

output "dashboards_load_balancer" {
  description = "The NLB's AWS DNS name and the URL to open OpenSearch Dashboards."
  value = local.lb == null ? null : {
    address = aws_lb.dashboards[0].dns_name
    url     = "${local.lb_port == 443 ? "https" : "http"}://${coalesce(local.lb.dns_name, aws_lb.dashboards[0].dns_name)}"
  }
}

output "extra_model_uuids" {
  description = "UUIDs of the models in `extra_models`, by name."
  value       = { for name in var.extra_models : name => juju_model.opensearch[name].uuid }
}

output "metadata" {
  description = "Metadata of the OpenSearch product deployment."
  value       = module.opensearch.metadata
}

output "offers" {
  description = "Map of all offers made by the OpenSearch product module."
  value       = module.opensearch.offers
}

output "opensearch_model_uuid" {
  description = "UUID of the OpenSearch model."
  value       = juju_model.opensearch[var.opensearch_model].uuid
}
