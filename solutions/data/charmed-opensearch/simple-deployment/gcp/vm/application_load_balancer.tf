# Copyright 2026 Canonical Ltd.
# See LICENSE file for licensing details.

resource "google_compute_region_url_map" "dashboards" {
  count           = local.lb_tls ? 1 : 0
  name            = "${var.opensearch_model}-dashboards"
  default_service = google_compute_region_backend_service.dashboards[0].id

  lifecycle {
    replace_triggered_by = [terraform_data.lb_mode[0]]
  }
}

resource "google_compute_region_target_https_proxy" "dashboards" {
  count                            = local.lb_tls ? 1 : 0
  name                             = "${var.opensearch_model}-dashboards"
  url_map                          = google_compute_region_url_map.dashboards[0].id
  certificate_manager_certificates = [local.lb.certificate_id]

  lifecycle {
    replace_triggered_by = [terraform_data.lb_mode[0]]
  }
}
