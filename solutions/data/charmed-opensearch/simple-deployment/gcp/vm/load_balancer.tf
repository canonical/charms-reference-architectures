# Copyright 2026 Canonical Ltd.
# See LICENSE file for licensing details.

data "google_compute_network" "dashboards" {
  count = local.lb == null ? 0 : 1
  name  = var.network
}

data "google_compute_subnetwork" "dashboards" {
  count = local.lb == null ? 0 : 1
  name  = local.lb.backend_subnet

  lifecycle {
    postcondition {
      condition     = self.network == data.google_compute_network.dashboards[0].self_link
      error_message = "The OpenSearch Dashboards backend subnet must belong to the selected network."
    }
    postcondition {
      condition     = !contains(local.excluded_subnets, self.ip_cidr_range)
      error_message = "The OpenSearch Dashboards backend subnet must not be an excluded subnet."
    }
  }
}

resource "google_compute_subnetwork" "proxy_only" {
  count         = try(local.lb.create_proxy_subnet, false) ? 1 : 0
  name          = "${var.opensearch_model}-dashboards-proxy-only"
  network       = var.network
  ip_cidr_range = local.lb.proxy_subnet_cidr
  purpose       = "REGIONAL_MANAGED_PROXY"
  role          = "ACTIVE"
}

# Juju tags each machine with its instance name.
resource "google_compute_firewall" "dashboards" {
  count         = local.lb == null ? 0 : 1
  name          = "${var.opensearch_model}-dashboards-lb"
  network       = var.network
  source_ranges = [local.lb.proxy_subnet_cidr, "35.191.0.0/16"]
  target_tags   = [for instance in local.dashboards_instances : instance.name]

  allow {
    protocol = "tcp"
    ports    = ["5601"]
  }
}

# New group names when the OpenSearch Dashboards machines change.
resource "terraform_data" "dashboards_backend" {
  count = length(local.dashboards_instances)
  triggers_replace = [
    local.dashboards_instances[count.index],
    var.network,
    data.google_compute_subnetwork.dashboards[0].self_link,
  ]

  lifecycle {
    create_before_destroy = true
  }
}

# One group per OpenSearch Dashboards machine.
resource "google_compute_network_endpoint_group" "dashboards" {
  count                 = length(local.dashboards_instances)
  name                  = "${substr(var.opensearch_model, 0, 36)}-dashboards-${count.index}-${substr(replace(terraform_data.dashboards_backend[count.index].id, "-", ""), 0, 12)}"
  zone                  = local.dashboards_instances[count.index].zone
  network               = var.network
  subnetwork            = data.google_compute_subnetwork.dashboards[0].self_link
  network_endpoint_type = "GCE_VM_IP_PORT"

  lifecycle {
    create_before_destroy = true
  }
}

resource "google_compute_network_endpoint" "dashboards" {
  count                  = length(local.dashboards_instances)
  network_endpoint_group = google_compute_network_endpoint_group.dashboards[count.index].name
  zone                   = google_compute_network_endpoint_group.dashboards[count.index].zone
  instance               = local.dashboards_instances[count.index].name
  ip_address             = local.dashboards_instances[count.index].ip
  port                   = 5601

  # Deleting the dedicated NEG removes this endpoint, even after Juju deletes its VM.
  deletion_policy = "ABANDON"

  lifecycle {
    create_before_destroy = true
  }
}

resource "google_compute_region_health_check" "dashboards" {
  count = local.lb == null ? 0 : 1
  name  = "${var.opensearch_model}-dashboards"

  tcp_health_check {
    port = 5601
  }
}

# A protocol or public/private change rebuilds the dependent load balancer resources.
resource "terraform_data" "lb_mode" {
  count            = local.lb == null ? 0 : 1
  triggers_replace = [local.lb_tls, local.lb_public]
}

resource "google_compute_region_backend_service" "dashboards" {
  count                 = local.lb == null ? 0 : 1
  name                  = "${var.opensearch_model}-dashboards"
  load_balancing_scheme = local.lb_scheme
  protocol              = local.lb_tls ? local.lb_http_protocol : "TCP"
  health_checks         = [google_compute_region_health_check.dashboards[0].id]
  security_policy       = local.lb_security_policy

  dynamic "backend" {
    for_each = google_compute_network_endpoint_group.dashboards

    content {
      group                        = backend.value.id
      balancing_mode               = local.lb_tls ? "RATE" : "CONNECTION"
      max_rate_per_endpoint        = local.lb_tls ? 100 : null
      max_connections_per_endpoint = local.lb_tls ? null : 100
      capacity_scaler              = 1
    }
  }

  # Populate new groups before switching backends and removing old groups.
  depends_on = [google_compute_network_endpoint.dashboards]

  lifecycle {
    replace_triggered_by = [terraform_data.lb_mode[0]]
  }
}

resource "google_compute_region_target_tcp_proxy" "dashboards" {
  count           = local.lb == null || local.lb_tls ? 0 : 1
  name            = "${var.opensearch_model}-dashboards"
  backend_service = google_compute_region_backend_service.dashboards[0].id
}

resource "google_compute_address" "dashboards" {
  count        = local.lb == null ? 0 : 1
  name         = "${var.opensearch_model}-dashboards"
  address_type = local.lb_public ? "EXTERNAL" : "INTERNAL"
  subnetwork   = local.lb_public ? null : local.lb.subnet
  network_tier = local.lb_public ? "STANDARD" : null
}

resource "google_compute_forwarding_rule" "dashboards" {
  count                 = local.lb == null ? 0 : 1
  name                  = "${var.opensearch_model}-dashboards"
  load_balancing_scheme = local.lb_scheme
  network               = var.network
  subnetwork            = local.lb_public ? null : local.lb.subnet
  network_tier          = local.lb_public ? "STANDARD" : null
  ip_address            = google_compute_address.dashboards[0].address
  ip_protocol           = "TCP"
  port_range            = local.lb_port
  target                = local.lb_tls ? google_compute_region_target_https_proxy.dashboards[0].id : google_compute_region_target_tcp_proxy.dashboards[0].id

  depends_on = [google_compute_subnetwork.proxy_only]

  lifecycle {
    replace_triggered_by = [terraform_data.lb_mode[0]]
  }
}

resource "google_dns_managed_zone" "dashboards" {
  count      = local.lb_dns_name == null || local.lb_public ? 0 : 1
  name       = "${var.opensearch_model}-dashboards"
  dns_name   = "${local.lb_dns_name}."
  visibility = "private"

  private_visibility_config {
    networks {
      network_url = data.google_compute_network.dashboards[0].id
    }
  }
}

resource "google_dns_record_set" "dashboards" {
  count        = local.lb_dns_name == null || local.lb_public ? 0 : 1
  managed_zone = google_dns_managed_zone.dashboards[0].name
  name         = "${local.lb_dns_name}."
  type         = "A"
  ttl          = 300
  rrdatas      = [local.lb_address]
}
