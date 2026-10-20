# Copyright 2026 Canonical Ltd.
# See LICENSE file for licensing details.

resource "juju_model" "opensearch" {
  name        = var.opensearch_model
  constraints = local.model_constraints == "" ? null : local.model_constraints

  config = {
    network = var.network
  }

  # Create the gateway subnet first, so Juju sees it when the model is created.
  depends_on = [azurerm_subnet.gateway]
}

resource "juju_space" "excluded" {
  count      = length(local.excluded_subnets) == 0 ? 0 : 1
  model_uuid = juju_model.opensearch.uuid
  name       = "excluded"
}

resource "juju_subnet" "excluded" {
  for_each   = toset(local.excluded_subnets)
  model_uuid = juju_model.opensearch.uuid
  cidr       = each.value
  space_name = juju_space.excluded[0].name
}

module "cos" {
  count  = local.cos_enabled ? 1 : 0
  source = "git::https://github.com/canonical/observability-stack//terraform/cos-lite?ref=tf-cos-lite-3.0.3"

  risk = var.cos.risk

  model = {
    name       = var.cos.model
    cloud      = { name = var.cos.cloud }
    credential = coalesce(var.cos.credential, var.cos.cloud)
  }

  traefik = {
    config = merge(
      { loadbalancer_annotations = "service.beta.kubernetes.io/azure-load-balancer-internal=true" },
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
  count      = local.cos_enabled ? 1 : 0
  name       = "opentelemetry-collector"
  model_uuid = juju_model.opensearch.uuid

  charm {
    name    = "opentelemetry-collector"
    channel = "0.130/stable"
    base    = local.base
  }
}

resource "juju_integration" "cos" {
  for_each   = local.cos_offers
  model_uuid = juju_model.opensearch.uuid

  application {
    name     = juju_application.opentelemetry_collector[0].name
    endpoint = each.key
  }

  application {
    offer_url = each.value
  }
}

module "opensearch" {
  source = "git::https://github.com/canonical/opensearch-operator//terraform/machine/product/simple_deployment?ref=efa6b48ea34b4cf5c03e19bbe5cfbaa662e8508f"

  opensearch = merge(var.opensearch, {
    channel    = local.opensearch_channel
    model_uuid = juju_model.opensearch.uuid
    base       = local.base
    expose     = length(var.opensearch.allowed_cidrs) == 0 ? [] : [{ cidrs = join(",", var.opensearch.allowed_cidrs) }]
  })

  offered_endpoints = var.offered_endpoints

  opensearch_dashboards = merge(var.opensearch_dashboards, {
    channel = local.dashboards_channel
    base    = local.base
    expose  = length(var.opensearch_dashboards.allowed_cidrs) == 0 ? [] : [{ cidrs = join(",", var.opensearch_dashboards.allowed_cidrs) }]
  })

  certificates_integration = local.certificates_integration

  data_integrator = merge(var.data_integrator, {
    constraints = var.integrator_constraints
    config      = merge({ "index-name" = "opensearch-index", "extra-user-roles" = "admin" }, var.data_integrator.config)
  })

  self_signed_certificates = {
    constraints = var.integrator_constraints
  }

  cos_agent_integration = local.cos_enabled ? {
    name     = juju_application.opentelemetry_collector[0].name
    endpoint = "cos-agent"
  } : null

  backups = var.backups == null ? null : {
    storage_type = "azure-storage"
    constraints  = var.integrator_constraints
    config = merge({
      storage-account     = var.backups.storage_account
      container           = var.backups.container
      path                = var.backups.path
      connection-protocol = "https"
    }, var.backups.config)
  }
  azure_storage_secret_key     = var.azure_storage_secret_key
  azure_storage_secret_version = var.backups == null ? 0 : var.azure_storage_secret_version

  depends_on = [juju_subnet.excluded]
}
