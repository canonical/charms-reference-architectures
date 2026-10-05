# Copyright 2026 Canonical Ltd.
# See LICENSE file for licensing details.

## ====================================================
## Provision and set up Bastion Host for juju (Optional)
## ====================================================

# Static external IP: survives instance stop/start and can be whitelisted
resource "google_compute_address" "bastion_public_ip" {
  # if PROVISION_BASTION is true then create the bastion host
  count  = var.PROVISION_BASTION ? 1 : 0
  name   = "bastion-public-ip"
  region = var.REGION

  depends_on = [google_project_service.compute]
}

resource "google_compute_instance" "bastion" {
  # if PROVISION_BASTION is true then create the bastion host
  count        = var.PROVISION_BASTION ? 1 : 0
  name         = "bastion"
  machine_type = "e2-standard-2"
  zone         = local.zone
  # Target of the allow_external firewall rule
  tags = ["bastion"]

  boot_disk {
    initialize_params {
      image = "ubuntu-os-cloud/ubuntu-2604-lts-amd64"
      size  = 20
      type  = "pd-balanced"
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.controller_subnet.id
    access_config {
      nat_ip = google_compute_address.bastion_public_ip[count.index].address
    }
  }

  # The Juju client on the bastion authenticates as this account through the
  # metadata server (Juju's service-account auth type)
  service_account {
    email  = google_service_account.juju[0].email
    scopes = ["cloud-platform"]
  }

  metadata = {
    ssh-keys = "ubuntu:${chomp(file(var.SSH_PUBLIC_KEY))}" # Path to your SSH public key
  }

  depends_on = [
    google_compute_address.bastion_public_ip,
    google_service_account.juju,
    google_project_iam_member.juju,
    google_compute_network.main_vpc,
    google_compute_subnetwork.controller_subnet,
  ]
}

resource "null_resource" "set_up_bastion_script" {
  count = var.PROVISION_BASTION ? 1 : 0
  provisioner "file" {
    content = templatefile("${path.module}/scripts/setup-juju-env.tftpl", {
      project_id             = var.PROJECT_ID,
      region                 = var.REGION,
      zone                   = local.zone,
      network_name           = google_compute_network.main_vpc.name,
      controller_subnet_name = google_compute_subnetwork.controller_subnet.name,
      controller_constraints = var.CONTROLLER_CONSTRAINTS,
      gke_cluster_name       = var.GKE_CLUSTER_NAME,
      sa_email               = google_service_account.juju[0].email,
      sa_key_path            = "",
    })
    destination = "setup-juju-env.sh"
  }

  provisioner "remote-exec" {
    # remote-exec only reports the last command's exit status, so the rm must
    # not run after a failed setup
    inline = ["bash ~/setup-juju-env.sh && rm ~/setup-juju-env.sh"]
  }

  connection {
    type        = "ssh"
    host        = google_compute_address.bastion_public_ip[0].address
    user        = "ubuntu"
    private_key = file(var.SSH_PRIVATE_KEY)
  }

  # Bootstrap must not race the IAM grants, and add-k8s needs nodes to exist
  depends_on = [
    google_compute_instance.bastion,
    google_compute_address.bastion_public_ip,
    google_project_iam_member.juju,
    google_service_account_iam_member.juju_act_as_default_compute,
    google_service_account_iam_member.juju_act_as_self,
    google_compute_network.main_vpc,
    google_compute_subnetwork.controller_subnet,
    google_compute_subnetwork.deployments_subnet,
    google_compute_firewall.allow_external,
    google_compute_firewall.allow_internal,
    google_compute_router_nat.nat,
    google_container_cluster.gke,
    google_container_node_pool.gke_nodes,
  ]
}
