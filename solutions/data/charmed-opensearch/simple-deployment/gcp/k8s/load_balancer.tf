# Copyright 2026 Canonical Ltd.
# See LICENSE file for licensing details.

variable "dashboards_load_balancer" {
  description = "OpenSearch Dashboards load balancer. Private by default; `public = true` exposes it to `allowed_cidrs`."
  type = object({
    public         = optional(bool, false)
    allowed_cidrs  = optional(set(string), [])
    hostname       = optional(string)
    name           = optional(string, "opensearch-dashboards")
    allow_priority = optional(number, 800)
    deny_priority  = optional(number, 900)
  })
  default  = {}
  nullable = false

  validation {
    condition     = var.dashboards_load_balancer.public ? length(var.dashboards_load_balancer.allowed_cidrs) > 0 : length(var.dashboards_load_balancer.allowed_cidrs) == 0
    error_message = "Set at least one CIDR in `allowed_cidrs` with `public = true`, and none without it."
  }

  validation {
    condition = alltrue([
      for cidr in var.dashboards_load_balancer.allowed_cidrs : can(cidrnetmask(cidr))
    ])
    error_message = "`dashboards_load_balancer.allowed_cidrs` must be IPv4 CIDRs."
  }

  validation {
    condition     = can(regex("^[a-z]([-a-z0-9]{0,55}[a-z0-9])?$", var.dashboards_load_balancer.name))
    error_message = "`dashboards_load_balancer.name` must be a GCP name of at most 57 characters: lowercase letters, digits and hyphens, starting with a letter."
  }

  validation {
    condition = (
      var.dashboards_load_balancer.allow_priority >= 0 &&
      floor(var.dashboards_load_balancer.allow_priority) == var.dashboards_load_balancer.allow_priority &&
      var.dashboards_load_balancer.allow_priority < var.dashboards_load_balancer.deny_priority &&
      floor(var.dashboards_load_balancer.deny_priority) == var.dashboards_load_balancer.deny_priority &&
      var.dashboards_load_balancer.deny_priority < 1000
    )
    error_message = "Use integer priorities 0 <= allow < deny < 1000, after checking effective organization/network policies."
  }

  validation {
    condition     = !var.dashboards_load_balancer.public || !contains(keys(var.dashboards_traefik.config), "loadbalancer_annotations")
    error_message = "`dashboards_traefik.config.loadbalancer_annotations` can't be used with `public = true`."
  }
}

# Switching public/private replaces Traefik; the firewall rules exist before it and outlive the old one.
resource "terraform_data" "frontend_topology" {
  triggers_replace = local.frontend_topology
}

resource "google_compute_address" "frontend" {
  count        = local.public_frontend ? 1 : 0
  name         = var.dashboards_load_balancer.name
  address_type = "EXTERNAL"
  network_tier = "PREMIUM"
}

resource "google_compute_firewall" "allow_clients" {
  count              = local.public_frontend ? 1 : 0
  name               = "${var.dashboards_load_balancer.name}-allow"
  network            = var.network
  direction          = "INGRESS"
  priority           = var.dashboards_load_balancer.allow_priority
  source_ranges      = sort(tolist(var.dashboards_load_balancer.allowed_cidrs))
  destination_ranges = ["${google_compute_address.frontend[0].address}/32"]
  allow {
    protocol = "tcp"
    ports    = ["80", "443"]
  }
}

resource "google_compute_firewall" "deny_other_clients" {
  count              = local.public_frontend ? 1 : 0
  name               = "${var.dashboards_load_balancer.name}-deny"
  network            = var.network
  direction          = "INGRESS"
  priority           = var.dashboards_load_balancer.deny_priority
  source_ranges      = ["0.0.0.0/0"]
  destination_ranges = ["${google_compute_address.frontend[0].address}/32"]
  deny {
    protocol = "tcp"
    ports    = ["80", "443"]
  }
}

output "dashboards_public_endpoint" {
  description = "The public load balancer's address and the URL to open OpenSearch Dashboards, or null when private."
  value = local.public_frontend ? {
    address       = google_compute_address.frontend[0].address
    hostname      = var.dashboards_load_balancer.hostname
    url           = "https://${coalesce(var.dashboards_load_balancer.hostname, google_compute_address.frontend[0].address)}/${var.opensearch_model}-${module.opensearch.app_names.opensearch_dashboards}"
    allowed_cidrs = var.dashboards_load_balancer.allowed_cidrs
  } : null
}
