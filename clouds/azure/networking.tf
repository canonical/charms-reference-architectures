# Copyright 2025 Canonical Ltd.
# See LICENSE file for licensing details.

## ====================================================
## Network infra
## ====================================================

resource "azurerm_virtual_network" "main_vnet" {
  name                = "main-vnet"
  address_space       = ["10.0.0.0/8"]
  location            = azurerm_resource_group.main_rg.location
  resource_group_name = azurerm_resource_group.main_rg.name
}

resource "azurerm_subnet" "controller_subnet" {
  name                 = "controller-subnet"
  resource_group_name  = azurerm_resource_group.main_rg.name
  virtual_network_name = azurerm_virtual_network.main_vnet.name
  address_prefixes     = ["10.1.0.0/16"]
}

resource "azurerm_subnet" "deployments_subnet" {
  name                 = "deployments-subnet"
  resource_group_name  = azurerm_resource_group.main_rg.name
  virtual_network_name = azurerm_virtual_network.main_vnet.name
  address_prefixes     = ["10.2.0.0/16"]
}


# --- NAT Gateway ---
# I. Controller NAT Gateway Setup
# 1. Create a dedicated Public IP for the NAT Gateway for the controller subnet
resource "azurerm_public_ip" "controller_nat_gateway_pip" {
  name                = "controller-nat-gateway-public-ip"
  resource_group_name = azurerm_resource_group.main_rg.name
  location            = azurerm_resource_group.main_rg.location
  allocation_method   = "Static"
  sku                 = "Standard"
}

# 2. Create the NAT Gateway resource
resource "azurerm_nat_gateway" "controller_nat_gateway" {
  name                = "controller-nat-gateway"
  resource_group_name = azurerm_resource_group.main_rg.name
  location            = azurerm_resource_group.main_rg.location
  sku_name            = "Standard"
}

# 3. Associate the Public IP with the NAT Gateway
resource "azurerm_nat_gateway_public_ip_association" "controller_nat_gateway_ip_assoc" {
  nat_gateway_id       = azurerm_nat_gateway.controller_nat_gateway.id
  public_ip_address_id = azurerm_public_ip.controller_nat_gateway_pip.id
}

# 4. Associate the NAT Gateway with the controller subnet
resource "azurerm_subnet_nat_gateway_association" "controller_subnet_nat_assoc" {
  subnet_id      = azurerm_subnet.controller_subnet.id
  nat_gateway_id = azurerm_nat_gateway.controller_nat_gateway.id
  depends_on = [
    azurerm_nat_gateway_public_ip_association.controller_nat_gateway_ip_assoc,
  ]
}

# II. Deployments NAT Gateway Setup
# 1. Create a dedicated Public IP for the NAT Gateway for the deployments subnet
resource "azurerm_public_ip" "deployments_nat_gateway_pip" {
  name                = "deployments-nat-gateway-public-ip"
  resource_group_name = azurerm_resource_group.main_rg.name
  location            = azurerm_resource_group.main_rg.location
  allocation_method   = "Static"
  sku                 = "Standard"
}

# 2. Create the NAT Gateway resource
resource "azurerm_nat_gateway" "deployments_nat_gateway" {
  name                = "deployments-nat-gateway"
  resource_group_name = azurerm_resource_group.main_rg.name
  location            = azurerm_resource_group.main_rg.location
  sku_name            = "Standard"
}

# 3. Associate the Public IP with the NAT Gateway
resource "azurerm_nat_gateway_public_ip_association" "deployments_nat_gateway_ip_assoc" {
  nat_gateway_id       = azurerm_nat_gateway.deployments_nat_gateway.id
  public_ip_address_id = azurerm_public_ip.deployments_nat_gateway_pip.id
}

# 4. Associate the NAT Gateway with the deployments subnet
resource "azurerm_subnet_nat_gateway_association" "deployments_subnet_nat_assoc" {
  subnet_id      = azurerm_subnet.deployments_subnet.id
  nat_gateway_id = azurerm_nat_gateway.deployments_nat_gateway.id
  depends_on = [
    azurerm_nat_gateway_public_ip_association.deployments_nat_gateway_ip_assoc,
  ]
}
