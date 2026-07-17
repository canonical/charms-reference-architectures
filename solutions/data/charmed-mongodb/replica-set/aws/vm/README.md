# Charmed MongoDB on AWS VMs

This Terraform root module deploys a three-unit Charmed MongoDB replica set on
AWS and composes it with the applications needed for a production-oriented
deployment:

- `data-integrator` for a MongoDB client application
- `self-signed-certificates` for MongoDB, etcd, and Vault TLS
- `charmed-etcd` for coordinated MongoDB rolling operations
- `vault` for MongoDB encryption at rest
- `opentelemetry-collector` and COS Lite for metrics, logs, and dashboards
- an optional `s3-integrator` or `gcs-integrator` for backups

MongoDB and its integrators are deployed by the
[`terraform/product/replica_set`](https://github.com/canonical/mongodb-operator/tree/DPE-10290-rs/terraform/product/replica_set)
module from the MongoDB operator.

The module source is temporarily pinned to `DPE-10290-rs`; change it to
`8/edge` after that branch has been merged.

## Requirements

- Terraform 1.6 or later
- Juju 3.6 or later and an accessible controller
- an AWS cloud and credential configured in Juju
- a Kubernetes cloud and credential named `k8s` for COS Lite (override these
  through `var.cos` if they use different names)

The Juju provider can be configured with `JUJU_CONTROLLER_ADDRESSES`,
`JUJU_USERNAME`, and `JUJU_PASSWORD`.

## Deploy

Create a `terraform.tfvars` file. The minimal deployment uses all defaults:

```hcl
mongodb_model = "mongodb"
```

To enable S3 backups, add:

```hcl
backups_integrator = {
  storage_type = "s3"
  config = {
    bucket   = "my-mongodb-backups"
    region   = "eu-west-3"
    endpoint = "https://s3.eu-west-3.amazonaws.com"
    path     = "mongodb"
  }
}

# Prefer TF_VAR_s3_access_key and TF_VAR_s3_secret_key in the environment.
```

Alternatively, to enable GCS backups, add:

```hcl
backups_integrator = {
  storage_type = "gcs"
  config = {
    bucket        = "my-mongodb-backups"
    path          = "mongodb"
    storage-class = "STANDARD"
  }
}

# Set TF_VAR_gcs_secret_key to the GCP service-account JSON document.
```

The `storage_type` selects the integrator. When `channel` is omitted, the
product module uses `2/stable` for S3 and `1/stable` for GCS.

Optional custom MongoDB client and peer TLS private keys can be supplied through
the sensitive `tls_client_private_key` and `tls_peer_private_key` variables.
Prefer setting them through `TF_VAR_tls_client_private_key` and
`TF_VAR_tls_peer_private_key` rather than committing them to a tfvars file.

Then run:

```bash
terraform init
terraform plan -out terraform.out
terraform apply terraform.out
```

## Required Vault bootstrap

Terraform deploys and relates Vault, but it deliberately does not initialize or
authorize it. After deployment, initialize/unseal Vault and authorize the charm
using the operational procedure for the
[`vault` charm](https://charmhub.io/vault/docs/h-initialize-vault). MongoDB's
encryption-at-rest integration will not become ready until that step is done.

The default certificate authority is intended to make the solution easy to
evaluate. Replace `self-signed-certificates` with the certificate provider used
by your organization when deploying into production.
