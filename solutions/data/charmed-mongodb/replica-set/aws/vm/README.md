# Terraform module for mongodb-operator

This Terraform root module facilitates the deployment of a Charmed MongoDB
replica set on AWS VMs using the
[Terraform Juju provider](https://github.com/juju/terraform-provider-juju/).
For more information, refer to the provider
[documentation](https://registry.terraform.io/providers/juju/juju/latest/docs).

The solution deploys MongoDB with a data integrator, TLS certificates,
OpenTelemetry Collector, and COS Lite. It can also integrate with an existing
Vault deployment for encryption at rest and an optional S3 integrator for
backups.

## Requirements

| Name | Version |
|------|---------|
| Terraform | >= 1.6 |
| Juju provider | ~> 2.0 |
| Juju | 3.6 or later |

An AWS cloud and credential must be configured in Juju. A Kubernetes cloud and
credential named `k8s` are used for COS Lite by default and can be overridden
through `var.cos`.

The Juju provider can be configured with `JUJU_CONTROLLER_ADDRESSES`,
`JUJU_USERNAME`, and `JUJU_PASSWORD`.

## Providers

| Name | Version |
|------|---------|
| `juju` | ~> 2.0 |

## Modules

| Name | Source |
|------|--------|
| `mongodb_replica_set` | `canonical/mongodb-operator//terraform/product/replica_set` (`8/edge`) |
| `cos` | `canonical/observability-stack//terraform/cos-lite` (`tf-cos-lite-3.0.2`) |

## Resources

| Name | Type |
|------|------|
| `juju_model.mongodb` | [Juju model](https://registry.terraform.io/providers/juju/juju/latest/docs/resources/model) |
| `juju_application.self_signed_certificates` | [Juju application](https://registry.terraform.io/providers/juju/juju/latest/docs/resources/application) |
| `juju_application.opentelemetry_collector` | [Juju application](https://registry.terraform.io/providers/juju/juju/latest/docs/resources/application) |
| `juju_integration.opentelemetry_collector_prometheus` | [Juju integration](https://registry.terraform.io/providers/juju/juju/latest/docs/resources/integration) |
| `juju_integration.opentelemetry_collector_loki` | [Juju integration](https://registry.terraform.io/providers/juju/juju/latest/docs/resources/integration) |
| `juju_integration.opentelemetry_collector_dashboards` | [Juju integration](https://registry.terraform.io/providers/juju/juju/latest/docs/resources/integration) |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| `mongodb_model` | Name of the AWS VM model | `string` | `"mongodb"` | no |
| `cos` | COS model, cloud, credential, and channel risk configuration | <pre>object({<br/>  model      = optional(string, "cos")<br/>  cloud      = optional(string, "k8s")<br/>  credential = optional(string, "k8s")<br/>  risk       = optional(string, "stable")<br/>})</pre> | `{}` | no |
| `mongodb` | MongoDB replica-set application configuration | <pre>object({<br/>  app_name           = optional(string, "mongodb")<br/>  base               = optional(string, "ubuntu@24.04")<br/>  channel            = optional(string, "8/stable")<br/>  config             = optional(map(string), { role = "replication" })<br/>  constraints        = optional(string, "arch=amd64")<br/>  endpoint_bindings  = optional(set(object({ space = string, endpoint = optional(string) })), [])<br/>  expose             = optional(list(object({ cidrs = optional(string), endpoints = optional(string), spaces = optional(string) })), [])<br/>  machines           = optional(set(string), null)<br/>  revision           = optional(number, null)<br/>  storage_directives = optional(map(string), {})<br/>  units              = optional(number, 3)<br/>})</pre> | `{}` | no |
| `data_integrator` | Data-integrator application configuration | <pre>object({<br/>  app_name           = optional(string, "data-integrator")<br/>  base               = optional(string, "ubuntu@24.04")<br/>  channel            = optional(string, "latest/stable")<br/>  config             = optional(map(string), { database-name = "mongodb", extra-user-roles = "admin" })<br/>  constraints        = optional(string, "arch=amd64")<br/>  endpoint_bindings  = optional(set(object({ space = string, endpoint = optional(string) })), [])<br/>  machines           = optional(set(string), null)<br/>  revision           = optional(number, null)<br/>  storage_directives = optional(map(string), {})<br/>  units              = optional(number, 1)<br/>})</pre> | `{}` | no |
| `s3_integrator` | Optional S3 backup-integrator configuration | <pre>object({<br/>  config      = map(string)<br/>  channel     = optional(string, "2/stable")<br/>  base        = optional(string, "ubuntu@24.04")<br/>  revision    = optional(number, null)<br/>  constraints = optional(string, "arch=amd64")<br/>  machines    = optional(set(string), [])<br/>})</pre> | `null` | no |
| `s3_access_key` | Optional AWS S3 access key | `string` (sensitive) | `null` | no |
| `s3_secret_key` | Optional AWS S3 secret key | `string` (sensitive) | `null` | no |
| `tls_client_private_key` | Optional PEM private key for MongoDB client-to-server TLS | `string` (sensitive) | `null` | no |
| `tls_peer_private_key` | Optional PEM private key for MongoDB peer-to-peer TLS | `string` (sensitive) | `null` | no |
| `logging_config` | Logging configuration used by the MongoDB replica-set module | `string` | `"<root>=INFO"` | no |
| `self_signed_certificates` | Self-signed-certificates application configuration | <pre>object({<br/>  app_name    = optional(string, "self-signed-certificates")<br/>  channel     = optional(string, "1/stable")<br/>  revision    = optional(number, null)<br/>  base        = optional(string, "ubuntu@24.04")<br/>  constraints = optional(string, "arch=amd64")<br/>  config      = optional(map(string), { ca-common-name = "MongoDB CA" })<br/>})</pre> | `{}` | no |
| `opentelemetry_collector` | OpenTelemetry Collector application configuration | <pre>object({<br/>  app_name    = optional(string, "opentelemetry-collector")<br/>  channel     = optional(string, "2/stable")<br/>  revision    = optional(number, null)<br/>  base        = optional(string, "ubuntu@24.04")<br/>  constraints = optional(string, "arch=amd64")<br/>  config      = optional(map(string), {})<br/>})</pre> | `{}` | no |
| `vault_kv_integration` | Optional existing Vault KV endpoint or offer for encryption at rest | <pre>object({<br/>  kind     = string<br/>  name     = optional(string, null)<br/>  endpoint = optional(string, null)<br/>  url      = optional(string, null)<br/>})</pre> | `null` | no |

## Outputs

| Name | Description |
|------|-------------|
| `components` | Map of all components deployed by the solution |
| `metadata` | Metadata of the MongoDB replica-set deployment |
| `models` | Map keyed by model UUID containing the components deployed in each model |
| `offers` | Map of offers exposed by the MongoDB replica-set module |

## Deploy

The module can be deployed without Vault. To enable encryption at rest using an
existing Vault KV endpoint, create a `terraform.tfvars` file containing:

```hcl
mongodb_model = "mongodb"

vault_kv_integration = {
  kind     = "endpoint"
  name     = "vault"
  endpoint = "vault-kv"
}
```

For Vault deployed in another model, provide its offer URL instead:

```hcl
vault_kv_integration = {
  kind = "offer"
  url  = "admin/vault.vault-kv"
}
```

This module does not deploy, initialize, unseal, authorize, or configure Vault.
The endpoint or offer must refer to an existing operational Vault deployment.
Follow the
[`vault` charm documentation](https://charmhub.io/vault/docs/h-initialize-vault)
to prepare it before applying this module.

To enable S3 backups, add:

```hcl
s3_integrator = {
  config = {
    bucket   = "my-mongodb-backups"
    region   = "eu-west-3"
    endpoint = "https://s3.eu-west-3.amazonaws.com"
    path     = "mongodb"
  }
}

# Prefer TF_VAR_s3_access_key and TF_VAR_s3_secret_key in the environment.
```

Optional custom MongoDB client and peer TLS private keys can be supplied through
the sensitive `tls_client_private_key` and `tls_peer_private_key` variables.
Prefer environment variables over committing private keys to a tfvars file.

Then run:

```bash
terraform init
terraform plan -out terraform.out
terraform apply terraform.out
```

The default certificate authority is intended for evaluation. Replace
`self-signed-certificates` with your organization's certificate provider for
production deployments.
