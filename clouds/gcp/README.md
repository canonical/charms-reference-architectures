# GCP Juju Infrastructure Terraform Module

This Terraform module provisions the Google Cloud infrastructure for a Juju deployment. It uses the [Google provider](https://registry.terraform.io/providers/hashicorp/google/latest/docs).

## How it works

The deployment has two Terraform root modules with separate lifecycles:

1. The `clouds/gcp/state` module creates a Google Cloud Storage bucket for the environment's Terraform state. The bucket does not exist yet, so this module keeps its own state locally.
2. The `clouds/gcp` module deploys the networking, the optional bastion host, the optional GKE cluster and the Juju setup. It stores its state in the bucket from the state module. Set that bucket in the `gcs` backend in `clouds/gcp/versions.tf` before you run `terraform init` for this module.

Keep the state bucket for as long as the environment exists. To remove a deployment, destroy the main module's resources first, then the state module's.

## Features

  * **API enablement.** Enables the Compute, Kubernetes Engine, IAM and Resource Manager APIs, so the module works on a fresh project.
  * **Networking.** Creates a custom-mode VPC with subnets for Juju controllers and deployments, peer and client subnets for binding Juju spaces, and a Cloud NAT for private egress.
  * **Bastion host.** Optionally provisions a bastion with a static external IP for administering the Juju environment. The bastion authenticates to Juju with an attached service account, so it stores no credential.
  * **Google Kubernetes Engine (GKE).** Optionally deploys a GKE cluster with private nodes for Juju's Kubernetes support.
  * **Firewall rules.** Adds VPC firewall rules for inbound traffic. With a bastion, only the bastion accepts traffic from outside the VPC.
  * **Host initialization.** Optionally sets up the local host with Juju and bootstraps the controller.

## Requirements

  * **Terraform.** Version `1.9` or higher.
  * **Google Cloud CLI.** Authenticated for Terraform with Application Default Credentials (`gcloud auth application-default login`), or `GOOGLE_CREDENTIALS` set to a service account key.
  * **IAM permissions.** The identity that runs Terraform needs:
    * Permission to create networks, instances, service accounts, IAM bindings and GKE clusters in the project, for example `roles/owner`, or `roles/editor` plus `roles/resourcemanager.projectIamAdmin` and `roles/iam.serviceAccountAdmin`.
    * `roles/iam.serviceAccountUser` to attach the Juju service account to the bastion.
    * `roles/iam.serviceAccountAdmin` or `roles/owner`, because the module grants the Juju service account `iam.serviceAccounts.actAs` on individual service accounts.
  * **Local host path only** (`SETUP_LOCAL_HOST=true`):
    * `gcloud` and `gke-gcloud-auth-plugin` on `PATH` when you provision a GKE cluster. The setup script authenticates with the Juju service account key, so you don't need `gcloud auth login`.
    * The project must allow service account key creation. Google's secure-by-default organization policies block it with `constraints/iam.managed.disableServiceAccountKeyCreation` in every organization created on or after 3 May 2024. An organization policy administrator can lift it for the project with `gcloud org-policies reset constraints/iam.managed.disableServiceAccountKeyCreation --project=<PROJECT_ID>`. The bastion path needs no key.
    * If you set `SOURCE_ADDRESSES`, include the local host's public IP so it can reach the GKE control plane. The Juju controller reaches the control plane from a Google Cloud external IP, so on this path the module also allows all Google Cloud IP ranges.
    * The setup script installs the Juju snap from the 3.6 channel and bootstraps the controller. It does not upgrade system packages or install Terraform.
    * The setup script writes the GKE kubeconfig to `~/.kube/juju-gke-config`. It leaves `~/.kube/config` and its current context unchanged.

### Organization policy caveats

  * `constraints/compute.vmExternalIpAccess` blocks the bastion's external IP. It also blocks Juju's machines, which get an ephemeral external IP by default.
  * OS Login enforcement (`constraints/compute.requireOsLogin`) disables the metadata SSH key the module uses to reach the bastion.
  * Juju attaches the project's default compute service account to every workload machine it creates, and to the controller on the local host path. The module grants the Juju service account `actAs` on that account, so the apply fails if someone deleted or disabled it.

## Module Inputs

| Name                     | Type           | Description | Required | Default |
| :----------------------- | :------------- | :---------- | :------- | :------ |
| `PROJECT_ID`             | `string`       | ID of the GCP project to deploy into. | Yes | `n/a` |
| `REGION`                 | `string`       | GCP region for all resources, for example `us-central1` or `europe-west1`. | No | `"us-central1"` |
| `ZONE`                   | `string`       | Zone of the bastion and the GKE cluster, in `REGION`. Unset means the first available zone of the region. The module looks it up on the first apply and keeps it afterwards. | No | `null` |
| `PROVISION_BASTION`      | `bool`         | Whether to provision a bastion host for access to the environment. | No | `true` |
| `SSH_PUBLIC_KEY`         | `string`       | Path to the SSH public key for the bastion. | Yes if `PROVISION_BASTION` is `true` | `null` |
| `SSH_PRIVATE_KEY`        | `string`       | Path to the SSH private key for the bastion. | Yes if `PROVISION_BASTION` is `true` | `null` |
| `SOURCE_ADDRESSES`       | `list(string)` | CIDR blocks that the inbound firewall rules and the GKE control plane public endpoint accept, for example `["1.2.3.4/32", "5.6.7.0/24"]`. Unset means unrestricted. With `SETUP_LOCAL_HOST`, the control plane also accepts all Google Cloud IP ranges. | No | `null` |
| `GKE_CLUSTER_NAME`       | `string`       | Name of the GKE cluster. Up to 40 lowercase letters, digits and hyphens, starting with a letter. Set to `""` to skip the GKE cluster. | No | `"gke-cluster"` |
| `GKE_NODE_COUNT`         | `number`       | Number of nodes in the GKE node pool. | No | `3` |
| `GKE_NODE_MACHINE_TYPE`  | `string`       | Machine type of the GKE node pool. The default allows many persistent disk attachments per node, for storage-heavy workloads. | No | `"n2-standard-16"` |
| `SETUP_LOCAL_HOST`       | `bool`         | Whether to set up the host machine with Juju and bootstrap the Juju controller. Mutually exclusive with `PROVISION_BASTION`. | No | `false` |
| `CONTROLLER_CONSTRAINTS` | `string`       | Juju constraints for the controller machine. With `cores` and `mem` constraints, Juju picks the cheapest matching type, often a new machine family that has run out of capacity. The default pins a widely available type. | No | `"instance-type=e2-standard-4"` |

---

## Module Outputs

| Name             | Description | Sensitive |
| :--------------- | :---------- | :-------- |
| `infrastructure` | Map of the created infrastructure: `project_id`, `network_name`, `controller_subnet_name`, `deployments_subnet_name`, `deployments_peers_subnet_name`, `deployments_clients_subnet_name`, and `bastion_public_ip` when you provision a bastion. | No |
| `gke_cluster`    | Map of the GKE cluster: `name`, `location`, `endpoint` and `ca_certificate`. | Yes |

---

## Usage

Deploy the state module first, then the main module.

### 1. Backend Configuration

Create the bucket for the Terraform state with the `clouds/gcp/state` module:

```shell
pushd clouds/gcp/state

terraform init

terraform plan -out terraform.out \
    -var="PROJECT_ID=my-project-id"  # required, your GCP project ID

terraform apply terraform.out

popd
```

The bucket name prefix defaults to `tfstate`. To change it, set `BUCKET_NAME` when you plan the state module:

```shell
-var="BUCKET_NAME=tfstateuniquetest"
```

The module appends a random suffix to keep the bucket name globally unique.

Copy the `bucket_name` output into the `backend "gcs"` block of `clouds/gcp/versions.tf`:

```terraform
  terraform {
    ...
    required_providers {
      ...
    }

    backend "gcs" {
      bucket = "tfstateXXXXXXXX" # replace with the bucket_name output of the state module
      prefix = "state"
    }
  }
```

### 2. Setup the GCP infrastructure

#### a. Standalone deployment

Write your variables to `clouds/gcp/terraform.tfvars`, which git ignores. Only `PROJECT_ID` is required. The other values below are defaults or examples, and [Module Inputs](#module-inputs) describes each one.

```terraform
PROJECT_ID = "my-project-id"

REGION = "us-central1"
# ZONE = "us-central1-b"  # defaults to the first available zone of REGION

# Bastion path (default). Set PROVISION_BASTION = false and SETUP_LOCAL_HOST = true
# to set up this machine with Juju instead.
PROVISION_BASTION = true
SSH_PUBLIC_KEY    = "~/.ssh/id_rsa.pub" # required when PROVISION_BASTION is true
SSH_PRIVATE_KEY   = "~/.ssh/id_rsa"     # required when PROVISION_BASTION is true
SETUP_LOCAL_HOST  = false

# Public IP of your host. Unset allows all addresses.
SOURCE_ADDRESSES = ["123.45.67.12/32"]

# Set GKE_CLUSTER_NAME = "" to skip the GKE cluster
GKE_CLUSTER_NAME      = "gke-cluster"
GKE_NODE_COUNT        = 3
GKE_NODE_MACHINE_TYPE = "n2-standard-16" # n2-standard-4 is enough for smaller workloads

CONTROLLER_CONSTRAINTS = "instance-type=e2-standard-4"
```

Then run:

```shell
pushd clouds/gcp

terraform init

terraform plan -out terraform.out

terraform apply terraform.out

popd
```

You can also pass variables with `-var` flags or environment variables such as `TF_VAR_PROJECT_ID`.

On a fresh project, the first apply can fail with an "API not enabled" or "service account does not exist" error while the API or service account propagates. Run `terraform apply` again.

#### b. Sourced as a module

Add a `module` block to your Terraform configuration:

```terraform
module "juju_gcp_infra" {
  source = "git::https://github.com/canonical/charms-reference-architectures//clouds/gcp?ref=main" # or a local path

  PROJECT_ID          = var.project_id
  REGION              = var.region
  PROVISION_BASTION   = var.provision_bastion
  SSH_PUBLIC_KEY      = var.ssh_public_key
  SSH_PRIVATE_KEY     = var.ssh_private_key
  SOURCE_ADDRESSES    = var.source_addresses
  GKE_CLUSTER_NAME    = var.gke_cluster_name
  SETUP_LOCAL_HOST    = var.setup_local_host
}
```

### GKE sizing

GKE limits how many persistent disks each node can attach, based on its machine type. Storage-heavy deployments such as a MongoDB sharded cluster need a machine type with enough attachments. More nodes (`GKE_NODE_COUNT`) add attachment capacity, and a larger `GKE_NODE_MACHINE_TYPE` can raise the per-node limit. Check the limit after provisioning with `kubectl get csinode`.

The default of three `n2-standard-16` nodes needs 48 N2 vCPUs in the region. New projects often have a lower regional quota. Request an increase, or use a smaller machine type or fewer nodes.

### Destroying the deployment

Destroy the Juju controller first. Juju creates instances, disks and firewall rules in the VPC that Terraform does not manage, and GCP refuses to delete a network that is still in use:

```shell
juju destroy-controller gcp --destroy-all-models --destroy-storage
```

Run this from the bastion, or from the local host on the `SETUP_LOCAL_HOST` path. Then destroy the main infrastructure before you delete the state bucket:

```shell
terraform plan -destroy -out=destroy.out
terraform apply destroy.out
```

If the controller did not shut down cleanly, delete the firewall rules and disks Juju created in the VPC by hand before you destroy the network.

The state bucket keeps every version of the state file, and GCS refuses to delete a bucket that still holds objects. Empty it before you destroy the state module:

```shell
gcloud storage rm --recursive --all-versions "gs://<bucket_name>/**"

pushd clouds/gcp/state
terraform destroy
popd
```

## License

This module is licensed under the [Apache License](../../LICENSE).
