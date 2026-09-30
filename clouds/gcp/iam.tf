# Copyright 2026 Canonical Ltd.
# See LICENSE file for licensing details.

## ====================================================
## Service account for the Juju controller
## ====================================================

# One account serves both paths. The bastion runs as it with service-account
# auth, and the local host uses a key file with jsonfile auth.

resource "google_service_account" "juju" {
  count        = local.juju_sa_enabled ? 1 : 0
  account_id   = "juju-controller"
  display_name = "Juju controller service account"

  depends_on = [google_project_service.iam]
}

resource "google_project_iam_member" "juju" {
  for_each = local.juju_sa_enabled ? toset(local.juju_roles) : toset([])
  project  = var.PROJECT_ID
  role     = each.value
  member   = "serviceAccount:${google_service_account.juju[0].email}"

  depends_on = [google_project_service.cloudresourcemanager]
}

# Juju needs actAs on each account it attaches to instances. Granting it per
# account stops the Juju account from acting as every account in the project.

# Workload machines, and the controller on the local-host path, get the
# project default compute service account
data "google_compute_default_service_account" "default" {
  count      = local.juju_sa_enabled ? 1 : 0
  depends_on = [google_project_service.compute]
}

resource "google_service_account_iam_member" "juju_act_as_default_compute" {
  count              = local.juju_sa_enabled ? 1 : 0
  service_account_id = data.google_compute_default_service_account.default[0].name
  role               = "roles/iam.serviceAccountUser"
  member             = "serviceAccount:${google_service_account.juju[0].email}"
}

# On the bastion path, where Juju uses the service-account auth type, the
# controller gets the Juju service account itself
resource "google_service_account_iam_member" "juju_act_as_self" {
  count              = var.PROVISION_BASTION ? 1 : 0
  service_account_id = google_service_account.juju[0].name
  role               = "roles/iam.serviceAccountUser"
  member             = "serviceAccount:${google_service_account.juju[0].email}"
}

# Key for the local-host path only. The bastion authenticates through the
# metadata server and never holds a secret.
resource "google_service_account_key" "juju" {
  count              = var.SETUP_LOCAL_HOST ? 1 : 0
  service_account_id = google_service_account.juju[0].name
}

# Juju re-reads the key from this path on later operations, so it stays on
# disk. The strictly confined juju snap can read the Juju data directory.
resource "local_sensitive_file" "juju_sa_key" {
  count           = var.SETUP_LOCAL_HOST ? 1 : 0
  content         = base64decode(google_service_account_key.juju[0].private_key)
  filename        = "${pathexpand("~")}/.local/share/juju/gcp-juju-sa-key.json"
  file_permission = "0600"
}
