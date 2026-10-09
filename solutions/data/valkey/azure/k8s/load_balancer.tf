# Copyright 2026 Canonical Ltd.
# See LICENSE file for licensing details.

locals {
  aks        = one(data.azurerm_kubernetes_cluster.this[*])
  valkey_app = module.valkey.credentials.valkey.app_name
}

data "azurerm_kubernetes_cluster" "this" {
  count               = var.load_balancer == null ? 0 : 1
  name                = var.load_balancer.aks_cluster
  resource_group_name = var.load_balancer.resource_group
}

# Reserved before Valkey so the server certificate can cover it. It sits in the node resource
# group, where the cluster identity may already attach it to the load balancer.
resource "azurerm_public_ip" "valkey" {
  count               = var.load_balancer == null ? 0 : 1
  name                = "${var.valkey_model}-valkey-external"
  resource_group_name = local.aks.node_resource_group
  location            = local.aks.location
  allocation_method   = "Static"
  sku                 = "Standard"
}

# Follows the primary: the charm moves the role=primary pod label on failover.
resource "kubernetes_service_v1" "valkey_external" {
  count = var.load_balancer == null ? 0 : 1

  metadata {
    name      = "${local.valkey_app}-external"
    namespace = var.valkey_model # Juju names the namespace after the model.

    annotations = {
      "service.beta.kubernetes.io/azure-pip-name" = azurerm_public_ip.valkey[0].name
    }
  }

  spec {
    type                        = "LoadBalancer"
    load_balancer_source_ranges = var.load_balancer.allowed_cidrs

    selector = {
      application-name = local.valkey_app
      role             = "primary"
    }

    port {
      name        = "valkey-tls"
      port        = module.valkey.credentials.valkey.tls_port
      target_port = module.valkey.credentials.valkey.tls_port
    }
  }
}

# AKS opens the port in the NSG it manages on the nodes' NICs. An NSG on the node subnet filters
# the same traffic and needs its own rule. The priority sits far above the ones Juju picks, which
# start at 200.
resource "azurerm_network_security_rule" "valkey_external" {
  count                       = try(var.load_balancer.network_security_group, null) == null ? 0 : 1
  name                        = "${var.valkey_model}-valkey-external"
  resource_group_name         = var.load_balancer.resource_group
  network_security_group_name = var.load_balancer.network_security_group
  priority                    = 4000
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_address_prefixes     = var.load_balancer.allowed_cidrs
  source_port_range           = "*"
  destination_address_prefix  = "*"
  destination_port_range      = tostring(module.valkey.credentials.valkey.tls_port)
}
