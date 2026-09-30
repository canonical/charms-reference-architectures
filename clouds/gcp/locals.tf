# Copyright 2026 Canonical Ltd.
# See LICENSE file for licensing details.

locals {
  zone = var.ZONE != null ? var.ZONE : terraform_data.zone[0].output

  # Firewall sources: everything when SOURCE_ADDRESSES is not set
  source_ranges = var.SOURCE_ADDRESSES == null ? ["0.0.0.0/0"] : var.SOURCE_ADDRESSES

  # Whether either Juju setup path is enabled
  juju_sa_enabled = var.PROVISION_BASTION || var.SETUP_LOCAL_HOST

  # Juju's docs also list Service Account Key Admin, but its 3.6 google
  # provider never calls the IAM API. iam.tf grants actAs per account.
  juju_roles = concat(
    [
      "roles/compute.instanceAdmin.v1",
      "roles/compute.securityAdmin",
    ],
    # get-credentials on the GKE cluster and the cluster-scoped RBAC objects
    # created by `juju add-k8s`
    var.GKE_CLUSTER_NAME != "" ? ["roles/container.admin"] : [],
  )
}
