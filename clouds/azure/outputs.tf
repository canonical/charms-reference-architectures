

output "infrastructure" {
  value = {
    resource_group_name     = azurerm_resource_group.main.name
    vnet_name               = azurerm_virtual_network.main.name
    controller_subnet_name  = azurerm_subnet.controller_subnet.name
    deployments_subnet_name = azurerm_subnet.deployments_subnet.name
    bastion_public_ip       = var.PROVISION_BASTION ? azurerm_public_ip.bastion_public_ip[0].ip_address : null
  }
}


output "aks_cluster" {
  value = var.AKS_CLUSTER_NAME != "" ? {
    name                = azurerm_kubernetes_cluster.aks[0].name
    resource_group_name = azurerm_kubernetes_cluster.aks[0].resource_group_name
    location            = azurerm_kubernetes_cluster.aks[0].location
    kube_config         = azurerm_kubernetes_cluster.aks[0].kube_config_raw
  } : null
  sensitive = true
}

