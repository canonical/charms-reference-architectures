# Copyright 2026 Canonical Ltd.
# See LICENSE file for licensing details.

# The collector pushes to Traefik's public load balancer from the machines' outbound IP, such as
# a NAT gateway's. An NSG on the AKS node subnet filters that traffic on top of the one AKS manages.
# The priority sits far above the ones Juju picks, which start at 200.
resource "azurerm_network_security_rule" "cos_ingress" {
  count                       = var.cos_ingress == null ? 0 : 1
  name                        = "${var.cos_model}-traefik"
  resource_group_name         = var.cos_ingress.resource_group
  network_security_group_name = var.cos_ingress.network_security_group
  priority                    = 4001
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_address_prefixes     = var.cos_ingress.allowed_cidrs
  source_port_range           = "*"
  destination_address_prefix  = "*"
  destination_port_ranges     = ["80", "443"]
}
