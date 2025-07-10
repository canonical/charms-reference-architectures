# Copyright 2025 Canonical Ltd.
# See LICENSE file for licensing details.

## ====================================================
## Provision and set up Bastion Host for juju (Optional)
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

# workaround for https://forum.snapcraft.io/t/not-a-snap-cgroup-error-when-running-chromium/33243/3
resource "null_resource" "set_up_bastion_script" {
  count = var.PROVISION_BASTION ? 1 : 0
  provisioner "file" {
    content = templatefile("scripts/setup-juju-env.tftpl", {
      rg_name                = azurerm_resource_group.main_rg.name,
      mi_name                = var.PROVISION_BASTION ? azurerm_user_assigned_identity.bastion_identity[0].name : "",
      subscription_id        = var.AZURE_SUBSCRIPTION_ID,
      region                 = var.REGION,
      kube_config            = var.AKS_CLUSTER_NAME != "" ? azurerm_kubernetes_cluster.aks[0].kube_config_raw : "",
      vnet_name              = azurerm_virtual_network.main_vnet.name,
      controller_subnet_name = azurerm_subnet.controller_subnet.name,
      aks_cluster_name       = var.AKS_CLUSTER_NAME != "" ? var.AKS_CLUSTER_NAME : "",
      app_client_id          = var.SETUP_LOCAL_HOST ? azuread_application.juju_app[0].client_id : "",
      app_password           = var.SETUP_LOCAL_HOST ? azuread_application_password.juju_app_password[0].value : "",
    })
    destination = "setup-juju-env.sh"
  }

  provisioner "remote-exec" {
    inline = [
      "bash ~/setup-juju-env.sh",
      "rm ~/setup-juju-env.sh",
    ]
  }

  connection {
    type        = "ssh"
    host        = azurerm_public_ip.bastion_public_ip[0].ip_address
    user        = "ubuntu"
    private_key = file(var.SSH_PRIVATE_KEY)
  }

  depends_on = [
    azurerm_linux_virtual_machine.bastion,
    azurerm_public_ip.bastion_public_ip
  ]
}
