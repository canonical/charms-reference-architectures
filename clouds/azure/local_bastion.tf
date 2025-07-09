# Copyright 2025 Canonical Ltd.
# See LICENSE file for licensing details.

## ====================================================
## Set up Host Machine for Juju Controller (Optional)
## ====================================================

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

