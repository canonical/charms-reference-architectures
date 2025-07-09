# Copyright 2025 Canonical Ltd.
# See LICENSE file for licensing details.

## ====================================================
## Provider Configuration
## ====================================================

provider "azurerm" {
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }
  subscription_id = var.AZURE_SUBSCRIPTION_ID
}

## ====================================================
## Base Resources
## ====================================================
resource "azurerm_resource_group" "main_rg" {
  name     = var.RESOURCE_GROUP_NAME
  location = var.REGION
}


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
    source_address_prefixes      = var.SOURCE_ADDRESS_PREFIXES == null ? ["0.0.0.0/0"] : concat(var.SOURCE_ADDRESS_PREFIXES, azurerm_virtual_network.main_vnet.address_space)
    destination_address_prefixes = azurerm_virtual_network.main_vnet.address_space
  }

  security_rule {
    name                         = "allow-juju-17070"
    priority                     = 110
    direction                    = "Inbound"
    access                       = "Allow"
    protocol                     = "Tcp"
    source_address_prefixes      = var.SOURCE_ADDRESS_PREFIXES == null ? ["0.0.0.0/0"] : concat(var.SOURCE_ADDRESS_PREFIXES, azurerm_virtual_network.main_vnet.address_space)
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
    source_address_prefixes    = var.SOURCE_ADDRESS_PREFIXES == null ? ["0.0.0.0/0"] : concat(var.SOURCE_ADDRESS_PREFIXES, azurerm_virtual_network.main_vnet.address_space)
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
    source_address_prefixes    = var.SOURCE_ADDRESS_PREFIXES == null ? ["0.0.0.0/0"] : concat(var.SOURCE_ADDRESS_PREFIXES, azurerm_virtual_network.main_vnet.address_space)
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


## ====================================================
## Kubernetes infra (AKS)
## ====================================================
resource "azurerm_kubernetes_cluster" "aks" {
  # if AKS_CLUSTER_NAME is not set, do not create the AKS cluster
  count               = var.AKS_CLUSTER_NAME != "" ? 1 : 0
  name                = var.AKS_CLUSTER_NAME
  location            = azurerm_resource_group.main_rg.location
  resource_group_name = azurerm_resource_group.main_rg.name
  dns_prefix          = "cos-cluster-dns"

  default_node_pool {
    name           = "default"
    node_count     = 3
    vm_size        = "Standard_D4s_v3" # Comparable to t3.xlarge (4 vCPU, 16GB RAM)
    vnet_subnet_id = azurerm_subnet.deployments_subnet.id
    zones          = [2, 3] # Spread nodes across Availability Zones
  }


  identity {
    type = "SystemAssigned"
  }

  # Enable Azure RBAC for Kubernetes authorization
  role_based_access_control_enabled = true

  network_profile {
    network_plugin = "azure"
    service_cidr   = "10.0.2.0/24"
    dns_service_ip = "10.0.2.10"
  }
}

## ====================================================
## Bastion Host (Optional)
## ====================================================

# Create managed identity to be used by the bastion
resource "azurerm_user_assigned_identity" "bastion_identity" {
  # if PROVISION_BASTION is true then create the bastion host
  count               = var.PROVISION_BASTION ? 1 : 0
  name                = "bastion-identity"
  location            = azurerm_resource_group.main_rg.location
  resource_group_name = azurerm_resource_group.main_rg.name
}

# create role definition for the managed identity
resource "azurerm_role_definition" "bastion_role" {
  # if PROVISION_BASTION is true then create the bastion host
  count       = var.PROVISION_BASTION ? 1 : 0
  name        = "BastionRGRole"
  scope       = azurerm_resource_group.main_rg.id
  description = "Role definition for a Juju controller (Resource Group Scope)"

  permissions {
    actions = [
      "Microsoft.Compute/*",
      "Microsoft.KeyVault/*",
      "Microsoft.Network/*",
      "Microsoft.Resources/*",
      "Microsoft.Storage/*",
      "Microsoft.ManagedIdentity/userAssignedIdentities/*",
    ]
  }

  # Defines the assignable scopes for this role.
  # This role can only be assigned within the created resource group.
  assignable_scopes = [
    azurerm_resource_group.main_rg.id,
  ]
}

# Assign the role to the managed identity
resource "azurerm_role_assignment" "bastion_role_assignment" {
  # if PROVISION_BASTION is true then create the bastion host
  count                = var.PROVISION_BASTION ? 1 : 0
  scope                = azurerm_role_definition.bastion_role[count.index].scope
  role_definition_name = azurerm_role_definition.bastion_role[count.index].name
  principal_id         = azurerm_user_assigned_identity.bastion_identity[count.index].principal_id
  principal_type       = "ServicePrincipal"

  depends_on = [
    azurerm_role_definition.bastion_role,
    azurerm_user_assigned_identity.bastion_identity,
  ]
}

# Create a public IP address for the bastion host
resource "azurerm_public_ip" "bastion_public_ip" {
  # if PROVISION_BASTION is true then create the bastion host
  count               = var.PROVISION_BASTION ? 1 : 0
  name                = "bastion-public-ip"
  location            = azurerm_resource_group.main_rg.location
  resource_group_name = azurerm_resource_group.main_rg.name
  allocation_method   = "Static"   # Static or Dynamic IP allocation
  sku                 = "Standard" # Standard or Basic, Standard is recommended for production
}

# Create a network interface for the bastion host
resource "azurerm_network_interface" "bastion_nic" {
  # if PROVISION_BASTION is true then create the bastion host
  count               = var.PROVISION_BASTION ? 1 : 0
  name                = "bastion-nic"
  location            = azurerm_resource_group.main_rg.location
  resource_group_name = azurerm_resource_group.main_rg.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.controller_subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.bastion_public_ip[count.index].id
  }
}

resource "azurerm_linux_virtual_machine" "bastion" {
  # if PROVISION_BASTION is true then create the bastion host
  count               = var.PROVISION_BASTION ? 1 : 0
  name                = "bastion"
  resource_group_name = azurerm_resource_group.main_rg.name
  location            = azurerm_resource_group.main_rg.location
  size                = "Standard_F4s_v2"
  admin_username      = "ubuntu"
  network_interface_ids = [
    azurerm_network_interface.bastion_nic[count.index].id,
  ]

  user_data = base64encode(templatefile("scripts/setup-juju-env.tftpl", {
    rg_name                = azurerm_resource_group.main_rg.name,
    mi_name                = var.PROVISION_BASTION ? azurerm_user_assigned_identity.bastion_identity[0].name : "",
    subscription_id        = var.AZURE_SUBSCRIPTION_ID,
    region                 = var.REGION,
    kube_config            = var.AKS_CLUSTER_NAME != "" ? azurerm_kubernetes_cluster.aks[0].kube_config_raw : "",
    vnet_name              = azurerm_virtual_network.main_vnet.name,
    controller_subnet_name = azurerm_subnet.controller_subnet.name,
    aks_cluster_name       = var.AKS_CLUSTER_NAME != "" ? var.AKS_CLUSTER_NAME : "",
    app_client_id          = var.INITIALIZE_HOST ? azuread_application.juju_app[0].client_id : "",
    app_password           = var.INITIALIZE_HOST ? azuread_application_password.juju_app_password[0].value : "",
  }))

  admin_ssh_key {
    username   = "ubuntu"
    public_key = file(var.SSH_PUBLIC_KEY) # Path to your SSH public key
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "ubuntu-24_04-lts"
    sku       = "server"
    version   = "latest"
  }

  identity {
    type = "UserAssigned"
    identity_ids = [
      azurerm_user_assigned_identity.bastion_identity[count.index].id,
    ]
  }

  depends_on = [azurerm_kubernetes_cluster.aks,
    azurerm_public_ip.bastion_public_ip,
    azurerm_role_definition.bastion_role,
    azurerm_role_assignment.bastion_role_assignment,
    azurerm_network_interface.bastion_nic,
    azurerm_user_assigned_identity.bastion_identity,
    azurerm_virtual_network.main_vnet,
    azurerm_subnet.controller_subnet,
  ]
}


# ## ====================================================
# ## Initialize Host Machine for Juju Controller (Optional)
# ## ====================================================

data "azurerm_client_config" "current" {}

# Set up azure app for credentials for juju
resource "azuread_application" "juju_app" {
  count        = var.INITIALIZE_HOST ? 1 : 0
  display_name = "juju-controller-app"
  owners       = [data.azurerm_client_config.current.object_id]
}

# Initialize a password for the application
resource "azuread_application_password" "juju_app_password" {
  count          = var.INITIALIZE_HOST ? 1 : 0
  application_id = azuread_application.juju_app[0].id
}

# Create a service principal for the application
resource "azuread_service_principal" "juju_sp" {
  count     = var.INITIALIZE_HOST ? 1 : 0
  client_id = azuread_application.juju_app[0].client_id
  owners    = [data.azurerm_client_config.current.object_id]
}

# Create a role assignment for the service principal
resource "azurerm_role_assignment" "juju_sp_role_assignment" {
  count                = var.INITIALIZE_HOST ? 1 : 0
  scope                = azurerm_resource_group.main_rg.id
  role_definition_name = "Owner"
  principal_id         = azuread_service_principal.juju_sp[0].object_id
  principal_type       = "ServicePrincipal"
}

# write a bash script to initialize the controller
resource "local_file" "host_set_up_script" {
  # if INITIALIZE_HOST is true then initialize the controller
  count    = var.INITIALIZE_HOST ? 1 : 0
  filename = "${path.module}/scripts/setup-juju-env.sh"
  content = templatefile("scripts/setup-juju-env.tftpl", {
    rg_name                = azurerm_resource_group.main_rg.name,
    mi_name                = "",
    subscription_id        = var.AZURE_SUBSCRIPTION_ID,
    region                 = var.REGION,
    kube_config            = var.AKS_CLUSTER_NAME != "" ? azurerm_kubernetes_cluster.aks[0].kube_config_raw : "",
    vnet_name              = azurerm_virtual_network.main_vnet.name,
    controller_subnet_name = azurerm_subnet.controller_subnet.name,
    aks_cluster_name       = var.AKS_CLUSTER_NAME != "" ? var.AKS_CLUSTER_NAME : "",
    app_client_id          = var.INITIALIZE_HOST ? azuread_application.juju_app[0].client_id : "",
    app_password           = var.INITIALIZE_HOST ? azuread_application_password.juju_app_password[0].value : "",
  })
  depends_on = [
    azurerm_kubernetes_cluster.aks,
    azuread_application.juju_app,
    azuread_application_password.juju_app_password,
    azuread_service_principal.juju_sp,
    azurerm_role_assignment.juju_sp_role_assignment,
    azurerm_virtual_network.main_vnet,
    azurerm_subnet.controller_subnet,
  ]
}

# Execute the script on the local host
resource "null_resource" "initialize_host" {
  count = var.INITIALIZE_HOST ? 1 : 0

  provisioner "local-exec" {
    command = "bash ${local_file.host_set_up_script[0].filename}"
  }

  depends_on = [
    azurerm_kubernetes_cluster.aks,
    azuread_application.juju_app,
    azuread_application_password.juju_app_password,
    azuread_service_principal.juju_sp,
    azurerm_role_assignment.juju_sp_role_assignment,
    local_file.host_set_up_script,
  ]
}

