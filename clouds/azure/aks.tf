# Copyright 2025 Canonical Ltd.
# See LICENSE file for licensing details.

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
