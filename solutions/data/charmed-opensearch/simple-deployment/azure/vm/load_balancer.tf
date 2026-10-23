# Copyright 2026 Canonical Ltd.
# See LICENSE file for licensing details.

data "juju_machine" "dashboards" {
  count                 = local.lb_target_count
  model_uuid            = juju_model.opensearch.uuid
  machine_id            = sort(tolist(local.dashboards_app.machines))[count.index]
  wait_for_ip_addresses = ["private"]

  lifecycle {
    precondition {
      condition     = length(local.dashboards_app.machines) == var.opensearch_dashboards.units
      error_message = "OpenSearch Dashboards does not have the requested number of machines yet. Apply again in a few minutes."
    }
  }
}

data "azurerm_virtual_network" "dashboards" {
  count               = local.lb == null ? 0 : 1
  name                = local.network_name
  resource_group_name = local.network_resource_group
}

data "azurerm_subnet" "dashboards" {
  count                = local.lb == null || local.lb_tls ? 0 : 1
  name                 = local.lb.subnet
  virtual_network_name = local.network_name
  resource_group_name  = local.network_resource_group
}

resource "azurerm_lb" "dashboards" {
  count               = local.lb == null || local.lb_tls ? 0 : 1
  name                = "${var.opensearch_model}-dashboards"
  resource_group_name = local.network_resource_group
  location            = local.lb_location
  sku                 = "Standard"

  frontend_ip_configuration {
    name                          = "dashboards"
    subnet_id                     = data.azurerm_subnet.dashboards[0].id
    private_ip_address_allocation = "Dynamic"
  }
}

resource "azurerm_lb_backend_address_pool" "dashboards" {
  count           = local.lb == null || local.lb_tls ? 0 : 1
  name            = "dashboards"
  loadbalancer_id = azurerm_lb.dashboards[0].id
}

resource "azurerm_lb_backend_address_pool_address" "dashboards" {
  count                   = local.lb_tls ? 0 : local.lb_target_count
  name                    = "dashboards-${count.index}"
  backend_address_pool_id = azurerm_lb_backend_address_pool.dashboards[0].id
  virtual_network_id      = local.lb_vnet_id
  ip_address              = local.lb_machine_ips[count.index]
}

resource "azurerm_lb_probe" "dashboards" {
  count           = local.lb == null || local.lb_tls ? 0 : 1
  name            = "dashboards"
  loadbalancer_id = azurerm_lb.dashboards[0].id
  protocol        = "Tcp"
  port            = 5601
}

resource "azurerm_lb_rule" "dashboards" {
  count                          = local.lb == null || local.lb_tls ? 0 : 1
  name                           = "dashboards"
  loadbalancer_id                = azurerm_lb.dashboards[0].id
  protocol                       = "Tcp"
  frontend_port                  = local.lb_port
  backend_port                   = 5601
  frontend_ip_configuration_name = "dashboards"
  backend_address_pool_ids       = [azurerm_lb_backend_address_pool.dashboards[0].id]
  probe_id                       = azurerm_lb_probe.dashboards[0].id

  load_distribution = local.lb_passthrough ? "SourceIP" : "Default"
}

resource "azurerm_private_dns_zone" "dashboards" {
  count               = local.lb_dns_name == null || local.lb_public ? 0 : 1
  name                = local.lb_dns_name
  resource_group_name = local.network_resource_group
}

resource "azurerm_private_dns_zone_virtual_network_link" "dashboards" {
  count                 = local.lb_dns_name == null || local.lb_public ? 0 : 1
  name                  = "${var.opensearch_model}-dashboards"
  resource_group_name   = local.network_resource_group
  private_dns_zone_name = azurerm_private_dns_zone.dashboards[0].name
  virtual_network_id    = local.lb_vnet_id
}

resource "azurerm_private_dns_a_record" "dashboards" {
  count               = local.lb_dns_name == null || local.lb_public ? 0 : 1
  name                = "@"
  zone_name           = azurerm_private_dns_zone.dashboards[0].name
  resource_group_name = local.network_resource_group
  ttl                 = 300
  records             = [local.lb_address]
}
