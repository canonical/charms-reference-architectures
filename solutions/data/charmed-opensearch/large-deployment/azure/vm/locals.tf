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

  dashboards_app = module.opensearch.models[juju_model.opensearch[var.opensearch_model].uuid].components.opensearch_dashboards

  excluded_subnets = distinct(concat(var.excluded_subnets, local.lb == null ? [] : [local.lb.subnet_cidr]))

  # One excluded subnet per model and CIDR, keyed like "opensearch-data/10.5.0.0/24".
  excluded_subnets_by_model = merge([
    for model in local.models : {
      for cidr in local.excluded_subnets : "${model}/${cidr}" => { model = model, cidr = cidr }
    }
  ]...)

  lb                = var.dashboards_load_balancer
  lb_address        = local.lb_public ? one(azurerm_public_ip.dashboards[*].ip_address) : (local.lb_tls ? cidrhost(local.lb.subnet_cidr, -2) : one(azurerm_lb.dashboards[*].private_ip_address))
  lb_bundled_ca     = local.lb_reencrypt && var.certificates_integration == null
  lb_ca_certificate = local.lb_bundled_ca ? jsondecode(juju_action.dashboards_ca[0].output)["ca-certificate"] : try(local.lb.ca_certificate, null)
  lb_dns_name       = try(local.lb.dns_name, null)
  lb_location       = one(data.azurerm_virtual_network.dashboards[*].location)
  lb_machine_ips    = data.juju_machine.dashboards[*].ip_addresses[0]
  lb_port           = local.lb_tls || var.opensearch_dashboards.tls ? 443 : 80
  lb_public         = try(local.lb.public, false)
  lb_reencrypt      = local.lb_tls && var.opensearch_dashboards.tls
  lb_target_count   = local.lb == null ? 0 : var.opensearch_dashboards.units
  lb_tls            = try(local.lb.key_vault_secret_id, null) != null
  lb_vnet_id        = one(data.azurerm_virtual_network.dashboards[*].id)
  model_constraints = trimspace("${length(local.excluded_subnets) == 0 ? "" : "spaces=alpha"} ${var.model_constraints}")
  models            = concat([var.opensearch_model], var.extra_models)

  network_name           = split("/", var.network)[1]
  network_resource_group = split("/", var.network)[0]
}
