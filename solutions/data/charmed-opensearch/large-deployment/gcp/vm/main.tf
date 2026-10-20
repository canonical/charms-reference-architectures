# Copyright 2026 Canonical Ltd.
# See LICENSE file for licensing details.

resource "juju_model" "opensearch" {
  for_each    = toset(local.models)
  name        = each.value
  constraints = local.model_constraints == "" ? null : local.model_constraints

  config = {
    vpc-id = var.network
  }

  depends_on = [google_compute_subnetwork.proxy_only]
}

resource "juju_space" "excluded" {
  for_each   = length(local.excluded_subnets) == 0 ? toset([]) : toset(local.models)
  model_uuid = juju_model.opensearch[each.key].uuid
  name       = "excluded"
}

resource "juju_subnet" "excluded" {
  for_each   = local.excluded_subnets_by_model
  model_uuid = juju_model.opensearch[each.value.model].uuid
  cidr       = each.value.cidr
  space_name = juju_space.excluded[each.value.model].name
}

# Keep OpenSearch Dashboards machines in the subnet used by their zonal NEGs.
resource "juju_space" "dashboards" {
  count      = local.lb == null ? 0 : 1
  model_uuid = juju_model.opensearch[var.opensearch_model].uuid
  name       = "dashboards"
}

resource "juju_subnet" "dashboards" {
  count      = local.lb == null ? 0 : 1
  model_uuid = juju_model.opensearch[var.opensearch_model].uuid
  cidr       = data.google_compute_subnetwork.dashboards[0].ip_cidr_range
  space_name = juju_space.dashboards[0].name
}

module "cos" {
  count  = local.cos_enabled ? 1 : 0
  source = "git::https://github.com/canonical/observability-stack//terraform/cos-lite?ref=tf-cos-lite-3.0.3"

  model = {
    name       = var.cos.model
    cloud      = { name = var.cos.cloud }
    credential = coalesce(var.cos.credential, var.cos.cloud)
  }

  traefik = {
    config = merge(
      { loadbalancer_annotations = "networking.gke.io/load-balancer-type=Internal" },
      var.cos.traefik_config,
    )
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

resource "juju_application" "opentelemetry_collector" {
  for_each   = local.cos_enabled ? toset(local.models) : toset([])
  name       = "opentelemetry-collector"
  model_uuid = juju_model.opensearch[each.key].uuid

  charm {
    name    = "opentelemetry-collector"
    channel = "0.130/stable"
    base    = local.base
  }
}

resource "juju_integration" "cos" {
  for_each   = local.cos_links
  model_uuid = juju_model.opensearch[each.value.model].uuid

  application {
    name     = juju_application.opentelemetry_collector[each.value.model].name
    endpoint = each.value.endpoint
  }

  application {
    offer_url = each.value.url
  }
}

module "opensearch" {
  source = "git::https://github.com/canonical/opensearch-operator//terraform/machine/product/large_deployment?ref=2/edge"

  main = merge(var.main, {
    config     = merge(var.main.config, { profile = var.opensearch_charm.profile })
    channel    = var.opensearch_charm.channel
    revision   = var.opensearch_charm.revision
    model_uuid = juju_model.opensearch[var.opensearch_model].uuid
    base       = local.base
    expose     = length(var.main.allowed_cidrs) == 0 ? [] : [{ cidrs = join(",", var.main.allowed_cidrs) }]
  })

  failover = var.failover == null ? null : merge(var.failover, {
    config        = merge(var.failover.config, { profile = var.opensearch_charm.profile })
    channel       = var.opensearch_charm.channel
    revision      = var.opensearch_charm.revision
    base          = local.base
    expose        = length(var.failover.allowed_cidrs) == 0 ? [] : [{ cidrs = join(",", var.failover.allowed_cidrs) }]
    model_uuid    = var.failover.model == null ? null : juju_model.opensearch[var.failover.model].uuid
    cos_collector = var.failover.model == null || !local.cos_enabled ? null : juju_application.opentelemetry_collector[var.failover.model].name
  })

  apps = [for app in var.apps : merge(app, {
    config        = merge(app.config, { profile = var.opensearch_charm.profile })
    channel       = var.opensearch_charm.channel
    revision      = var.opensearch_charm.revision
    base          = local.base
    expose        = length(app.allowed_cidrs) == 0 ? [] : [{ cidrs = join(",", app.allowed_cidrs) }]
    model_uuid    = app.model == null ? null : juju_model.opensearch[app.model].uuid
    cos_collector = app.model == null || !local.cos_enabled ? null : juju_application.opentelemetry_collector[app.model].name
  })]

  offered_endpoints = var.offered_endpoints

  opensearch_dashboards = merge(var.opensearch_dashboards, {
    base              = local.base
    constraints       = local.lb == null ? var.opensearch_dashboards.constraints : "${var.opensearch_dashboards.constraints} spaces=${juju_space.dashboards[0].name}"
    endpoint_bindings = local.lb == null ? [] : [{ space = juju_space.dashboards[0].name }]
    expose            = length(var.opensearch_dashboards.allowed_cidrs) == 0 ? [] : [{ cidrs = join(",", var.opensearch_dashboards.allowed_cidrs) }]
  })

  certificates_integration = local.certificates_integration

  data_integrator = {
    constraints = var.integrator_constraints
    config      = merge({ "index-name" = "opensearch-index", "extra-user-roles" = "admin" }, var.data_integrator.config)
  }

  self_signed_certificates = {
    constraints = var.integrator_constraints
  }

  cos_agent_integration = local.cos_enabled ? {
    name     = juju_application.opentelemetry_collector[var.opensearch_model].name
    endpoint = "cos-agent"
  } : null

  backups = var.backups == null ? null : {
    storage_type = "gcs"
    constraints  = var.integrator_constraints
    config = merge({
      bucket = var.backups.bucket
      path   = var.backups.path
    }, var.backups.config)
  }
  gcs_secret_key     = var.gcs_secret_key
  gcs_secret_version = var.backups == null ? 0 : var.gcs_secret_version

  depends_on = [juju_subnet.excluded, juju_subnet.dashboards]
}
