# Copyright 2026 Canonical Ltd.
# See LICENSE file for licensing details.

variable "dashboards_load_balancer" {
  description = "OpenSearch Dashboards load balancer. Private by default; `public = true` exposes it to `allowed_cidrs`."
  type = object({
    public        = optional(bool, false)
    allowed_cidrs = optional(set(string), [])
    hostname      = optional(string)
  })
  default  = {}
  nullable = false

  # traefik accepts 1 CIDR in its annotations
  validation {
    condition     = length(var.dashboards_load_balancer.allowed_cidrs) == (var.dashboards_load_balancer.public ? 1 : 0)
    error_message = "Set exactly one CIDR in `allowed_cidrs` with `public = true`, and none without it."
  }

  validation {
    condition = alltrue([
      for cidr in var.dashboards_load_balancer.allowed_cidrs : can(cidrnetmask(cidr))
    ])
    error_message = "`dashboards_load_balancer.allowed_cidrs` must be IPv4 CIDRs."
  }

  validation {
    condition     = !var.dashboards_load_balancer.public || !contains(keys(var.dashboards_traefik.config), "loadbalancer_annotations")
    error_message = "`dashboards_traefik.config.loadbalancer_annotations` can't be used with `public = true`."
  }
}

# Switching `public` replaces Traefik, so its load balancer is created with the new setting.
resource "terraform_data" "dashboards_load_balancer_mode" {
  triggers_replace = var.dashboards_load_balancer.public
}

locals {
  traefik_name = trimprefix(juju_application.traefik.id, "${juju_application.traefik.model_uuid}:")
}

locals {
  dashboards_annotations = (
    var.dashboards_load_balancer.public
    ? "${local.public_load_balancer},service.beta.kubernetes.io/load-balancer-source-ranges=${one(var.dashboards_load_balancer.allowed_cidrs)}"
    : local.internal_load_balancer
  )

  traefik_frontend_config = merge(
    {
      loadbalancer_annotations = local.dashboards_annotations
      "csr-subject-attributes" = "CN=opensearch-dashboards"
    },
    var.dashboards_load_balancer.hostname == null ? {} : { external_hostname = var.dashboards_load_balancer.hostname },
  )
}
