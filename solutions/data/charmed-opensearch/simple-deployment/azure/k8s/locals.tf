# Copyright 2026 Canonical Ltd.
# See LICENSE file for licensing details.

locals {
  certificates_integration = var.certificates_integration == null ? null : {
    kind = "offer", name = null, endpoint = null, url = var.certificates_integration.url
  }

  collector   = local.cos_enabled ? juju_application.opentelemetry_collector[0].name : null
  cos_enabled = var.cos != null

  cos_offers = local.cos_enabled ? {
    grafana-dashboards-provider = module.cos[0].offers.grafana_dashboards.url
    send-loki-logs              = module.cos[0].offers.loki_logging.url
    send-remote-write           = module.cos[0].offers.prometheus_receive_remote_write.url
  } : {}

  dashboards_annotations = (
    var.dashboards_load_balancer.public
    ? "${local.public_load_balancer},service.beta.kubernetes.io/load-balancer-source-ranges=${one(var.dashboards_load_balancer.allowed_cidrs)}"
    : local.internal_load_balancer
  )

  dashboards_channel     = coalesce(var.opensearch_dashboards.channel, "2/${var.risk}")
  internal_load_balancer = "service.beta.kubernetes.io/azure-load-balancer-internal=true"
  opensearch_channel     = coalesce(var.opensearch.channel, "2/${var.risk}")
  public_load_balancer   = "service.beta.kubernetes.io/azure-load-balancer-internal=false"
  k8s_credential         = coalesce(var.k8s_credential, var.k8s_cloud)

  traefik_certificates = (
    var.dashboards_traefik.certificates_integration != null ? { kind = "offer", name = null, endpoint = null, url = var.dashboards_traefik.certificates_integration.url } :
    var.certificates_integration != null ? local.certificates_integration :
    { kind = "endpoint", name = module.opensearch.app_names.self_signed_certificates, endpoint = "certificates", url = null }
  )

  traefik_frontend_config = merge(
    {
      loadbalancer_annotations = local.dashboards_annotations
      "csr-subject-attributes" = "CN=opensearch-dashboards"
    },
    var.dashboards_load_balancer.hostname == null ? {} : { external_hostname = var.dashboards_load_balancer.hostname },
  )

  traefik_name = trimprefix(juju_application.traefik.id, "${juju_application.traefik.model_uuid}:")
}
