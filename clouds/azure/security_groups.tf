# Copyright 2025 Canonical Ltd.
# See LICENSE file for licensing details.

## ====================================================
## Network Security Group for SSH Access
## ====================================================

resource "azurerm_network_security_group" "main_nsg" {
  name                = "main-nsg"
  location            = azurerm_resource_group.main_rg.location
  resource_group_name = azurerm_resource_group.main_rg.name

  security_rule {
    name                         = "AllowSSH"
    priority                     = 100
    direction                    = "Inbound"
    access                       = "Allow"
    protocol                     = "Tcp"
    source_port_range            = "*"
    destination_port_range       = "22"
    source_address_prefixes      = var.SOURCE_ADDRESSES == null ? ["0.0.0.0/0"] : concat(var.SOURCE_ADDRESSES, azurerm_virtual_network.main_vnet.address_space)
    destination_address_prefixes = azurerm_virtual_network.main_vnet.address_space
  }

  security_rule {
    name                         = "allow-juju-17070"
    priority                     = 110
    direction                    = "Inbound"
    access                       = "Allow"
    protocol                     = "Tcp"
    source_address_prefixes      = var.SOURCE_ADDRESSES == null ? ["0.0.0.0/0"] : concat(var.SOURCE_ADDRESSES, azurerm_virtual_network.main_vnet.address_space)
    destination_address_prefixes = azurerm_virtual_network.main_vnet.address_space
    source_port_range            = "*"
    destination_port_range       = "17070"
  }

  # Ping (ICMP)
  security_rule {
    name                         = "allow-icmp"
    priority                     = 120
    direction                    = "Inbound"
    access                       = "Allow"
    protocol                     = "Icmp"
    source_address_prefixes      = azurerm_virtual_network.main_vnet.address_space
    destination_address_prefixes = azurerm_virtual_network.main_vnet.address_space
    source_port_range            = "*"
    destination_port_range       = "*"
  }

  security_rule {
    name                       = "AllowHTTP"
    priority                   = 140
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefixes    = var.SOURCE_ADDRESSES == null ? ["0.0.0.0/0"] : concat(var.SOURCE_ADDRESSES, azurerm_virtual_network.main_vnet.address_space)
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "AllowHTTPS"
    priority                   = 140
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefixes    = var.SOURCE_ADDRESSES == null ? ["0.0.0.0/0"] : concat(var.SOURCE_ADDRESSES, azurerm_virtual_network.main_vnet.address_space)
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "allow-outbound"
    priority                   = 130
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "0.0.0.0/0"
    source_port_range          = "*"
    destination_port_range     = "*"
  }

}

resource "azurerm_subnet_network_security_group_association" "controller_subnet_nsg_assoc" {
  subnet_id                 = azurerm_subnet.controller_subnet.id
  network_security_group_id = azurerm_network_security_group.main_nsg.id
}

resource "azurerm_subnet_network_security_group_association" "deployments_subnet_nsg_assoc" {
  subnet_id                 = azurerm_subnet.deployments_subnet.id
  network_security_group_id = azurerm_network_security_group.main_nsg.id
}
