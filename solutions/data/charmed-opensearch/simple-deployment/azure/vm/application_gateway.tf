# Copyright 2026 Canonical Ltd.
# See LICENSE file for licensing details.

# The gateway needs its own empty subnet.
resource "azurerm_subnet" "gateway" {
  count                = local.lb == null ? 0 : 1
  name                 = "${var.opensearch_model}-dashboards-gateway"
  resource_group_name  = local.network_resource_group
  virtual_network_name = local.network_name
  address_prefixes     = [local.lb.subnet_cidr]
  service_endpoints    = local.lb_tls ? ["Microsoft.KeyVault"] : []

  delegation {
    name = "application-gateway"

    service_delegation {
      name    = "Microsoft.Network/applicationGateways"
      actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
    }
  }
}

resource "juju_action" "dashboards_ca" {
  count            = local.lb_bundled_ca ? 1 : 0
  model_uuid       = juju_model.opensearch.uuid
  application_name = module.opensearch.app_names.self_signed_certificates
  unit             = "${module.opensearch.app_names.self_signed_certificates}/leader"
  action_name      = "get-ca-certificate"
}

resource "terraform_data" "lb_mode" {
  count            = local.lb_tls ? 1 : 0
  triggers_replace = [local.lb_public]
}

resource "azurerm_application_gateway" "dashboards" {
  count               = local.lb_tls ? 1 : 0
  name                = "${var.opensearch_model}-dashboards"
  resource_group_name = local.network_resource_group
  location            = local.lb_location

  # Add the subnet firewall before the gateway.
  depends_on = [azurerm_subnet_network_security_group_association.gateway]

  lifecycle {
    replace_triggered_by = [terraform_data.lb_mode[0]]
  }

  sku {
    name = "Standard_v2"
    tier = "Standard_v2"
  }

  autoscale_configuration {
    min_capacity = 0
  }

  identity {
    type         = "UserAssigned"
    identity_ids = [local.lb.key_vault_identity_id]
  }

  gateway_ip_configuration {
    name      = "dashboards"
    subnet_id = azurerm_subnet.gateway[0].id
  }

  frontend_ip_configuration {
    name                          = "dashboards"
    public_ip_address_id          = local.lb_public ? azurerm_public_ip.dashboards[0].id : null
    subnet_id                     = local.lb_public ? null : azurerm_subnet.gateway[0].id
    private_ip_address            = local.lb_public ? null : local.lb_address
    private_ip_address_allocation = local.lb_public ? null : "Static"
  }

  frontend_port {
    name = "dashboards"
    port = 443
  }

  ssl_certificate {
    name                = "dashboards"
    key_vault_secret_id = local.lb.key_vault_secret_id
  }

  http_listener {
    name                           = "dashboards"
    frontend_ip_configuration_name = "dashboards"
    frontend_port_name             = "dashboards"
    protocol                       = "Https"
    ssl_certificate_name           = "dashboards"
  }

  dynamic "trusted_root_certificate" {
    for_each = local.lb_reencrypt ? [local.lb_ca_certificate] : []

    content {
      name = "dashboards"
      data = base64encode(trusted_root_certificate.value)
    }
  }

  backend_address_pool {
    name         = "dashboards"
    ip_addresses = local.lb_machine_ips
  }

  backend_http_settings {
    name                           = "dashboards"
    port                           = 5601
    protocol                       = local.lb_reencrypt ? "Https" : "Http"
    cookie_based_affinity          = "Disabled"
    trusted_root_certificate_names = local.lb_reencrypt ? ["dashboards"] : null
    sni_validation_enabled         = false
  }

  request_routing_rule {
    name                       = "dashboards"
    priority                   = 100
    rule_type                  = "Basic"
    http_listener_name         = "dashboards"
    backend_address_pool_name  = "dashboards"
    backend_http_settings_name = "dashboards"
  }
}
