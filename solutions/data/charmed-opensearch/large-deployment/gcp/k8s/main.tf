# Copyright 2026 Canonical Ltd.
# See LICENSE file for licensing details.

resource "juju_model" "opensearch" {
  for_each   = toset(local.models)
  name       = each.value
  credential = local.k8s_credential

  cloud {
    name = var.k8s_cloud
  }

  # Full destroy waits for namespace/Service cleanup before releasing guards.
  # depends_on covers every model; only the main model holds the public Service.
  depends_on = [
    google_compute_firewall.allow_clients,
    google_compute_firewall.deny_other_clients,
  ]
}

module "cos" {
  count  = local.cos_enabled ? 1 : 0
  source = "git::https://github.com/canonical/observability-stack//terraform/cos-lite?ref=tf-cos-lite-3.0.3"

  risk = var.cos.risk

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
  model_uuid = juju_model.opensearch[var.opensearch_model].uuid
  trust      = true

  charm {
    name    = "traefik-k8s"
    channel = "latest/candidate"
  }

  config = merge(
    {
      "csr-subject-attributes" = "CN=opensearch-dashboards"
      loadbalancer_annotations = local.internal_load_balancer
    },
    var.dashboards_load_balancer.hostname == null ? {} : { external_hostname = var.dashboards_load_balancer.hostname },
    var.dashboards_traefik.config,
    local.public_frontend ? {
      loadbalancer_annotations = join(",", [
        "cloud.google.com/l4-rbs=enabled",
        "cloud.google.com/network-tier=Premium",
        "networking.gke.io/load-balancer-ip-addresses=${google_compute_address.frontend[0].name}",
      ])
    } : {},
  )

  lifecycle {
    replace_triggered_by = [terraform_data.frontend_topology]
  }
}

resource "juju_integration" "traefik_tls" {
  model_uuid = juju_model.opensearch[var.opensearch_model].uuid

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
  for_each   = local.cos_enabled ? toset(local.models) : toset([])
  name       = "opentelemetry-collector-k8s"
  model_uuid = juju_model.opensearch[each.key].uuid
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
  for_each   = local.cos_links
  model_uuid = juju_model.opensearch[each.value.model].uuid

  application {
    name     = local.collectors[each.value.model]
    endpoint = each.value.endpoint
  }

  application {
    offer_url = each.value.url
  }
}

module "opensearch" {
  source = "git::https://github.com/canonical/opensearch-operator//terraform/kubernetes/product/large_deployment?ref=efa6b48ea34b4cf5c03e19bbe5cfbaa662e8508f"

  main = merge(var.main, {
    config     = merge(var.main.config, { profile = var.opensearch_charm.profile })
    channel    = local.opensearch_channel
    revision   = var.opensearch_charm.revision
    resources  = var.opensearch_charm.resources
    model_uuid = juju_model.opensearch[var.opensearch_model].uuid
  })

  failover = var.failover == null ? null : merge(var.failover, {
    config        = merge(var.failover.config, { profile = var.opensearch_charm.profile })
    channel       = local.opensearch_channel
    revision      = var.opensearch_charm.revision
    resources     = var.opensearch_charm.resources
    model_uuid    = var.failover.model == null ? null : juju_model.opensearch[var.failover.model].uuid
    cos_collector = var.failover.model == null ? null : lookup(local.collectors, var.failover.model, null)
  })

  apps = [for app in var.apps : merge(app, {
    config        = merge(app.config, { profile = var.opensearch_charm.profile })
    channel       = local.opensearch_channel
    revision      = var.opensearch_charm.revision
    resources     = var.opensearch_charm.resources
    model_uuid    = app.model == null ? null : juju_model.opensearch[app.model].uuid
    cos_collector = app.model == null ? null : lookup(local.collectors, app.model, null)
  })]

  offered_endpoints = var.offered_endpoints

  opensearch_dashboards = merge(var.opensearch_dashboards, { channel = local.dashboards_channel })

  ingress_integration = {
    kind     = "endpoint"
    name     = local.traefik_name
    endpoint = "ingress"
  }

  certificates_integration = local.certificates_integration

  data_integrator = merge(var.data_integrator, {
    config = merge({ "index-name" = "opensearch-index", "extra-user-roles" = "admin" }, var.data_integrator.config)
  })

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
    storage_type = "gcs"
    config = merge({
      bucket = var.backups.bucket
      path   = var.backups.path
    }, var.backups.config)
  }
  gcs_secret_key     = var.gcs_secret_key
  gcs_secret_version = var.backups == null ? 0 : var.gcs_secret_version
}
