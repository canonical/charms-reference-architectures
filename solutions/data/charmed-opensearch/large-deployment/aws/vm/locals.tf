# Copyright 2026 Canonical Ltd.
# See LICENSE file for licensing details.

locals {
  base = "ubuntu@24.04"

  certificates_integration = var.certificates_integration == null ? null : {
    kind = "offer", name = null, endpoint = null, url = var.certificates_integration.url
  }

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

  cross_model        = length(distinct([for app in values(local.opensearch_units) : app.model])) > 1
  dashboards_channel = coalesce(var.opensearch_dashboards.channel, "2/${var.risk}")

  excluded_subnets_by_model = merge([
    for model in local.models : {
      for cidr in var.excluded_subnets : "${model}/${cidr}" => { model = model, cidr = cidr }
    }
  ]...)

  dashboards_app = module.opensearch.models[juju_model.opensearch[var.opensearch_model].uuid].components.opensearch_dashboards

  lb                 = var.dashboards_load_balancer
  lb_dns_name        = try(local.lb.dns_name, null)
  lb_public          = try(local.lb.public, false)
  lb_passthrough     = !local.lb_tls && var.opensearch_dashboards.tls
  lb_port            = local.lb_tls || var.opensearch_dashboards.tls ? 443 : 80
  lb_subnet_ids      = length(try(local.lb.subnet_ids, [])) > 0 ? sort(tolist(local.lb.subnet_ids)) : [for ids in values(local.lb_subnets_by_zone) : sort(ids)[0]]
  lb_subnets         = [for subnet in data.aws_subnet.vpc : subnet if !contains(var.excluded_subnets, subnet.cidr_block)]
  lb_subnets_by_zone = { for subnet in local.lb_subnets : subnet.availability_zone => subnet.id... }
  lb_target_count    = local.lb == null ? 0 : var.opensearch_dashboards.units
  lb_tls             = try(local.lb.certificate_arn, null) != null
  model_constraints  = trimspace("${var.model_constraints} ${length(var.excluded_subnets) == 0 ? "" : "spaces=alpha"}")
  models             = concat([var.opensearch_model], var.extra_models)
  opensearch_channel = coalesce(var.opensearch_charm.channel, "2/${var.risk}")

  opensearch_machines = local.cross_model ? {
    for unit in flatten([
      for app, settings in local.opensearch_units : [for index in range(settings.units) : { app = app, index = index }]
    ]) : "${unit.app}/${unit.index}" => unit
  } : {}

  opensearch_units = merge(
    { main = { model = var.opensearch_model, units = var.main.units } },
    var.failover == null ? {} : { failover = { model = coalesce(var.failover.model, var.opensearch_model), units = var.failover.units } },
    { for app in var.apps : app.app_name => { model = coalesce(app.model, var.opensearch_model), units = app.units } },
  )
}
