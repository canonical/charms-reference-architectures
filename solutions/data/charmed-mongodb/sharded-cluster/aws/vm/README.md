# Terraform module for a Charmed MongoDB sharded cluster on AWS VMs

This Terraform root module deploys a MongoDB sharded cluster with the
[Terraform Juju provider](https://github.com/juju/terraform-provider-juju/).
It uses the MongoDB operator's `terraform/product/sharded_cluster` module.

The deployment uses three distinct AWS models:

- The config-server model contains the config server, mongos, data integrator,
  optional S3 integrator, self-signed-certificates, and charmed etcd.
- The first shard is deployed in the shard-one model.
- The second shard is deployed in the shard-two model.

The certificate and etcd endpoints are offered from the config-server model so
the product module can integrate both remote shards. Charmed etcd is related to
self-signed-certificates through its `client-certificates` endpoint.

## Requirements

| Name | Version |
|------|---------|
| Terraform | >= 1.6 |
| Juju provider | ~> 2.0 |

An AWS cloud and credential must be configured in Juju. Provider credentials
can be supplied with `JUJU_CONTROLLER_ADDRESSES`, `JUJU_USERNAME`, and
`JUJU_PASSWORD`.

## Modules

| Name | Source |
|------|--------|
| `mongodb_sharded_cluster` | `canonical/mongodb-operator//terraform/product/sharded_cluster` (`8/edge`) |

## Resources

| Name | Type |
|------|------|
| `juju_model.config_server` | Juju model |
| `juju_model.shard_one` | Juju model |
| `juju_model.shard_two` | Juju model |
| `juju_application.self_signed_certificates` | Juju application |
| `juju_application.etcd` | Juju application |
| `juju_integration.etcd_client_certificates` | Juju integration |
| `juju_offer.certificates` | Juju offer |
| `juju_offer.etcd` | Juju offer |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| `models` | Names of the config-server, shard-one, and shard-two AWS models | `object` | `{}` | no |
| `config_server` | MongoDB config-server application configuration | `object` | `{}` | no |
| `mongos` | Mongos application configuration | `object` | `{}` | no |
| `shards` | Exactly two shard application configurations | `list(object)` | `[{ app_name = "shard-one" }, { app_name = "shard-two" }]` | no |
| `data_integrator` | Data-integrator configuration | `object` | `{}` | no |
| `s3_integrator` | Optional S3 integrator configuration | `object` | `null` | no |
| `self_signed_certificates` | Self-signed-certificates configuration | `object` | `{}` | no |
| `etcd` | Charmed etcd configuration | `object` | `{}` | no |
| `s3_access_key` | Optional S3 access key | `string` (sensitive) | `null` | no |
| `s3_secret_key` | Optional S3 secret key | `string` (sensitive) | `null` | no |
| `tls_client_private_key` | Optional config-server client TLS private key | `string` (sensitive) | `null` | no |
| `tls_peer_private_key` | Optional config-server peer TLS private key | `string` (sensitive) | `null` | no |
| `logging_config` | MongoDB product-module logging configuration | `string` | `"<root>=INFO"` | no |

## Outputs

| Name | Description |
|------|-------------|
| `components` | Map of all deployed components |
| `metadata` | Sharded-cluster deployment metadata |
| `models` | Map keyed by model UUID with components deployed in each model |
| `offers` | Map of offers exposed by the solution |
| `provides` | Map of provided integration endpoints |
| `requires` | Map of required integration endpoints |

## Deploy

The default configuration creates the three models and deploys two three-unit
shards:

```bash
terraform init
terraform plan -out terraform.out
terraform apply terraform.out
```

To enable S3 backups, add the following to `terraform.tfvars`:

```hcl
s3_integrator = {
  config = {
    bucket   = "my-mongodb-backups"
    region   = "eu-west-3"
    endpoint = "https://s3.eu-west-3.amazonaws.com"
    path     = "mongodb"
  }
}
```
