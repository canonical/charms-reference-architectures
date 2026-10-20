# Copyright 2026 Canonical Ltd.
# See LICENSE file for licensing details.

locals {
  certificates_integration = var.certificates_integration == null ? null : {
    kind = "offer", name = null, endpoint = null, url = var.certificates_integration.url
  }

  collector   = lookup(local.collectors, var.opensearch_model, null)
  collectors  = { for model, collector in juju_application.opentelemetry_collector : model => collector.name }
  cos_enabled = var.cos != null

  cos_links = merge([
    for model in local.models : {
      for endpoint, url in local.cos_offers : "${model}/${endpoint}" => { model = model, endpoint = endpoint, url = url }
    }
  ]...)

  cos_offers = local.cos_enabled ? {
    grafana-dashboards-provider = module.cos[0].offers.grafana_dashboards.url
    send-loki-logs              = module.cos[0].offers.loki_logging.url
    send-remote-write           = module.cos[0].offers.prometheus_receive_remote_write.url
  } : {}

  internal_load_balancer = "networking.gke.io/load-balancer-type=Internal"
  k8s_credential         = coalesce(var.k8s_credential, var.k8s_cloud)
  models                 = concat([var.opensearch_model], var.extra_models)

  traefik_certificates = (
    var.dashboards_traefik.certificates_integration != null ? { kind = "offer", name = null, endpoint = null, url = var.dashboards_traefik.certificates_integration.url } :
    var.certificates_integration != null ? local.certificates_integration :
    { kind = "endpoint", name = module.opensearch.app_names.self_signed_certificates, endpoint = "certificates", url = null }
  )
}
