# Copyright 2026 Canonical Ltd.
# See LICENSE file for licensing details.

resource "azurerm_public_ip" "dashboards" {
  count               = local.lb_public ? 1 : 0
  name                = "${var.opensearch_model}-dashboards"
  resource_group_name = local.network_resource_group
  location            = local.lb_location
  allocation_method   = "Static"
  sku                 = "Standard"
  ip_version          = "IPv4"
}

# Firewall for the gateway's subnet: the allow-list plus the access Azure needs.
resource "azurerm_network_security_group" "gateway" {
  count               = local.lb_public ? 1 : 0
  name                = "${var.opensearch_model}-dashboards-gateway"
  resource_group_name = local.network_resource_group
  location            = local.lb_location

  security_rule {
    name                       = "allow-clients"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefixes    = local.lb.allowed_cidrs
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "allow-gateway-manager"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "65200-65535"
    source_address_prefix      = "GatewayManager"
    destination_address_prefix = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "gateway" {
  count                     = local.lb_public ? 1 : 0
  subnet_id                 = azurerm_subnet.gateway[0].id
  network_security_group_id = azurerm_network_security_group.gateway[0].id
}
