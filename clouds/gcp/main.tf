# Copyright 2026 Canonical Ltd.
# See LICENSE file for licensing details.

## ====================================================
## Provider Configuration
## ====================================================

provider "google" {
  project = var.PROJECT_ID
  region  = var.REGION
}

## ====================================================
## Base Resources
## ====================================================

# Enables the APIs so the module works on a fresh project. Terraform can't
# infer which resources need which API, so they depend on it explicitly.
resource "google_project_service" "compute" {
  service            = "compute.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "container" {
  service            = "container.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "iam" {
  service            = "iam.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "cloudresourcemanager" {
  service            = "cloudresourcemanager.googleapis.com"
  disable_on_destroy = false
}

# Some regions have no zone "a", so the module looks up the zone when ZONE is
# unset. depends_on defers the read until the module enables the Compute API.
data "google_compute_zones" "available" {
  count      = var.ZONE == null ? 1 : 0
  region     = var.REGION
  status     = "UP"
  depends_on = [google_project_service.compute]
}

# Keeps the first zone found. The lookup can later change or become unknown,
# and a new zone would replace the bastion and the GKE cluster.
resource "terraform_data" "zone" {
  count            = var.ZONE == null ? 1 : 0
  input            = data.google_compute_zones.available[0].names[0]
  triggers_replace = var.REGION

  lifecycle {
    ignore_changes = [input]
  }
}
