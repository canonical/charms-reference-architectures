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

  dashboards_app            = module.opensearch.models[juju_model.opensearch[var.opensearch_model].uuid].components.opensearch_dashboards
  dashboards_channel        = coalesce(var.opensearch_dashboards.channel, "2/${var.risk}")
  dashboards_machine_zones  = try(data.external.dashboards_instances[0].result, {})
  dashboards_instance_names = sort(keys(local.dashboards_machine_zones))
  dashboards_instances = [
    for instance in data.google_compute_instance.dashboards : {
      name = instance.name
      zone = instance.zone
      ip   = one([for nic in instance.network_interface : nic.network_ip if nic.network == data.google_compute_network.dashboards[0].self_link])
    }
  ]
  excluded_subnets = distinct(concat(var.excluded_subnets, local.lb == null ? [] : [local.lb.proxy_subnet_cidr]))

  # One excluded subnet per model and CIDR, keyed like "opensearch-data/10.5.0.0/23".
  excluded_subnets_by_model = merge([
    for model in local.models : {
      for cidr in local.excluded_subnets : "${model}/${cidr}" => { model = model, cidr = cidr }
    }
  ]...)

  lb               = var.dashboards_load_balancer
  lb_address       = one(google_compute_address.dashboards[*].address)
  lb_dns_name      = try(local.lb.dns_name, null)
  lb_http_protocol = var.opensearch_dashboards.tls ? "HTTPS" : "HTTP"
  lb_public        = try(local.lb.public, false)
  lb_scheme        = local.lb_public ? "EXTERNAL_MANAGED" : "INTERNAL_MANAGED"
  lb_create_policy = local.lb_public && try(local.lb.security_policy, null) == null
  lb_security_policy = local.lb_public ? (
    local.lb.security_policy != null ? local.lb.security_policy : one(google_compute_region_security_policy.dashboards[*].id)
  ) : null
  lb_passthrough     = !local.lb_tls && var.opensearch_dashboards.tls
  lb_port            = local.lb_tls || var.opensearch_dashboards.tls ? 443 : 80
  lb_tls             = try(local.lb.certificate_id, null) != null
  model_constraints  = trimspace("${length(local.excluded_subnets) == 0 ? "" : "spaces=alpha"} ${var.model_constraints}")
  models             = concat([var.opensearch_model], var.extra_models)
  opensearch_channel = coalesce(var.opensearch_charm.channel, "2/${var.risk}")
  zones              = data.google_compute_zones.available.names
}
