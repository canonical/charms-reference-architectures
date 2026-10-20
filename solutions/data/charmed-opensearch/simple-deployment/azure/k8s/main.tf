# Copyright 2026 Canonical Ltd.
# See LICENSE file for licensing details.

resource "juju_model" "opensearch" {
  name       = var.opensearch_model
  credential = local.k8s_credential

  cloud {
    name = var.k8s_cloud
  }
}

module "cos" {
  count  = local.cos_enabled ? 1 : 0
  source = "git::https://github.com/canonical/observability-stack//terraform/cos-lite?ref=tf-cos-lite-3.0.3"

  model = {
    name       = var.cos.model
    cloud      = { name = var.k8s_cloud }
    credential = local.k8s_credential
  }

  traefik = {
    config = merge({ loadbalancer_annotations = local.internal_load_balancer }, var.cos.traefik_config)
  }

  grafana = {
    storage_directives = var.cos.grafana_storage_directives
  }

  loki = {
    storage_directives = var.cos.loki_storage_directives
  }

  prometheus = {
    storage_directives = var.cos.prometheus_storage_directives
  }
}

resource "juju_application" "traefik" {
  name       = "traefik-k8s"
  model_uuid = juju_model.opensearch.uuid
  trust      = true

  charm {
    name    = "traefik-k8s"
    channel = "latest/candidate"
  }

  config = merge(local.traefik_frontend_config, var.dashboards_traefik.config)

  lifecycle {
    replace_triggered_by = [terraform_data.dashboards_load_balancer_mode]
  }
}

resource "juju_integration" "traefik_tls" {
  model_uuid = juju_model.opensearch.uuid

  application {
    name     = local.traefik_name
    endpoint = "certificates"
  }

  application {
    name      = local.traefik_certificates.kind == "endpoint" ? local.traefik_certificates.name : null
    endpoint  = local.traefik_certificates.kind == "endpoint" ? local.traefik_certificates.endpoint : null
    offer_url = local.traefik_certificates.kind == "offer" ? local.traefik_certificates.url : null
  }
}

resource "juju_application" "opentelemetry_collector" {
  count      = local.cos_enabled ? 1 : 0
  name       = "opentelemetry-collector-k8s"
  model_uuid = juju_model.opensearch.uuid
  trust      = true

  charm {
    name    = "opentelemetry-collector-k8s"
    channel = "0.130/stable"
  }

  config = {
    tls_insecure_skip_verify = "true"
  }
}

resource "juju_integration" "cos" {
  for_each   = local.cos_offers
  model_uuid = juju_model.opensearch.uuid

  application {
    name     = local.collector
    endpoint = each.key
  }

  application {
    offer_url = each.value
  }
}

module "opensearch" {
  source = "git::https://github.com/canonical/opensearch-operator//terraform/kubernetes/product/simple_deployment?ref=2/edge"

  opensearch = merge(var.opensearch, {
    model_uuid = juju_model.opensearch.uuid
  })

  offered_endpoints = var.offered_endpoints

  opensearch_dashboards = var.opensearch_dashboards

  ingress_integration = {
    kind     = "endpoint"
    name     = local.traefik_name
    endpoint = "ingress"
  }

  certificates_integration = local.certificates_integration

  data_integrator = {
    config = merge({ "index-name" = "opensearch-index", "extra-user-roles" = "admin" }, var.data_integrator.config)
  }

  metrics_endpoint_integration = local.cos_enabled ? {
    kind     = "endpoint"
    name     = local.collector
    endpoint = "metrics-endpoint"
  } : null

  logging_integration = local.cos_enabled ? {
    kind     = "endpoint"
    name     = local.collector
    endpoint = "receive-loki-logs"
  } : null

  grafana_dashboard_integration = local.cos_enabled ? {
    kind     = "endpoint"
    name     = local.collector
    endpoint = "grafana-dashboards-consumer"
  } : null

  backups = var.backups == null ? null : {
    storage_type = "azure-storage"
    config = merge({
      storage-account     = var.backups.storage_account
      container           = var.backups.container
      path                = var.backups.path
      connection-protocol = "https"
    }, var.backups.config)
  }
  azure_storage_secret_key     = var.azure_storage_secret_key
  azure_storage_secret_version = var.backups == null ? 0 : var.azure_storage_secret_version

  depends_on = [kubernetes_daemon_set_v1.node_settings]
}
