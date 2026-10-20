# Copyright 2026 Canonical Ltd.
# See LICENSE file for licensing details.

resource "google_compute_region_security_policy" "dashboards" {
  count = local.lb_create_policy ? 1 : 0
  name  = "${var.opensearch_model}-dashboards"
  type  = "CLOUD_ARMOR"

  # Cloud Armor accepts up to ten source ranges in each rule.
  dynamic "rules" {
    for_each = chunklist(sort(tolist(local.lb.allowed_cidrs)), 10)

    content {
      action   = "allow"
      priority = 1000 + rules.key

      match {
        versioned_expr = "SRC_IPS_V1"
        config {
          src_ip_ranges = rules.value
        }
      }
    }
  }

  rules {
    action   = "deny(403)"
    priority = 2147483647

    match {
      versioned_expr = "SRC_IPS_V1"
      config {
        src_ip_ranges = ["*"]
      }
    }
  }
}
