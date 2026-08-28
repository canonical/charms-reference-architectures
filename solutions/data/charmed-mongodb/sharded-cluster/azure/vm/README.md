# Terraform module for MongoDB Sharded Cluster

This Terraform root module facilitates the deployment of a Charmed MongoDB
sharded cluster on Azure VMs using the
[Terraform Juju provider](https://github.com/juju/terraform-provider-juju/).
For more information, refer to the provider
[documentation](https://registry.terraform.io/providers/juju/juju/latest/docs).

The solution deploys a MongoDB sharded cluster with config server, mongos, 
multiple shards, data integrator, etcd for rolling operations, TLS certificates,
OpenTelemetry Collector, and COS Lite. It can also integrate with existing LDAP
and Vault deployments.

The deployment uses a scalable number of Azure VM models:

- The config-server model contains the config server, mongos, data integrator,
  and self-signed-certificates for MongoDB TLS.
- Dynamic shard models: Each shard is deployed in its own model with either 
  custom names or auto-generated names (mongodb-shard-1, mongodb-shard-2, etc.)
- The mongodb-etcd model (hardcoded name) contains charmed etcd with its own 
  self-signed-certificates for rolling operations.

## Requirements

| Name          | Version      |
| ------------- | ------------ |
| Terraform     | >= 1.6       |
| Juju provider | ~> 2.0       |
| Juju          | 3.6 or later |

An Azure cloud and credential must be configured in Juju. A Kubernetes cloud and
credential named `k8s` are used for COS Lite by default and can be overridden
through `var.cos`.

The Juju provider can be configured with `JUJU_CONTROLLER_ADDRESSES`,
`JUJU_USERNAME`, and `JUJU_PASSWORD`.

## Providers

| Name   | Version   |
| ------ | --------- |
| `juju` | ~> 2.0    |

## Modules

| Name                       | Source                                                                    |
| -------------------------- | ------------------------------------------------------------------------- |
| `mongodb_sharded_cluster`  | `canonical/mongodb-operator//terraform/product/sharded_cluster` (`8/edge`) |
| `charmed_etcd`             | `canonical/charmed-etcd-operator//terraform/charm` (`3.6/edge`)              |
| `cos`                      | `canonical/observability-stack//terraform/cos-lite` (`tf-cos-lite-3.0.2`) |
| `self_signed_certificates` | `canonical/self-signed-certificates-operator//terraform` (`main`)         |

## Resources

| Name                                                  | Type                                                                                                    |
| ----------------------------------------------------- | ------------------------------------------------------------------------------------------------------- |
| `juju_model.config_server`                           | [Juju model](https://registry.terraform.io/providers/juju/juju/latest/docs/resources/model)             |
| `juju_model.shards`                                   | [Juju model](https://registry.terraform.io/providers/juju/juju/latest/docs/resources/model)             |
| `juju_model.etcd`                                     | [Juju model](https://registry.terraform.io/providers/juju/juju/latest/docs/resources/model)             |
| `juju_application.opentelemetry_collector_config`    | [Juju application](https://registry.terraform.io/providers/juju/juju/latest/docs/resources/application) |
| `juju_application.opentelemetry_collector_shards`    | [Juju application](https://registry.terraform.io/providers/juju/juju/latest/docs/resources/application) |
| `juju_integration.opentelemetry_collector_prometheus` | [Juju integration](https://registry.terraform.io/providers/juju/juju/latest/docs/resources/integration) |
| `juju_integration.opentelemetry_collector_loki`       | [Juju integration](https://registry.terraform.io/providers/juju/juju/latest/docs/resources/integration) |
| `juju_integration.opentelemetry_collector_dashboards` | [Juju integration](https://registry.terraform.io/providers/juju/juju/latest/docs/resources/integration) |
| `juju_offer.certificates`                             | [Juju offer](https://registry.terraform.io/providers/juju/juju/latest/docs/resources/offer)             |
| `juju_offer.etcd`                                     | [Juju offer](https://registry.terraform.io/providers/juju/juju/latest/docs/resources/offer)             |

## Inputs

| Name                                    | Description                                                                                                                                                                                       | Type                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       | Default                                                                          | Required   |
| --------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------- | :--------: |
| `remote_state`                          | Azure Storage configuration for the infrastructure remote state                                                                                                                                   | <pre>object({<br/>  resource_group_name  = optional(string, "tfstate-rg")<br/>  storage_account_name = string<br/>  container_name       = optional(string, "tfstate")<br/>  key                  = optional(string, "infra.terraform.tfstate")<br/>})</pre>                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                               | n/a                                                                              | yes        |
| `models`                                | Centralized model names for config-server and shards                                                                                                                                             | <pre>object({<br/>  config_server = optional(string, "mongodb-config")<br/>  shards        = optional(list(string), ["mongodb-shard-one", "mongodb-shard-two"])<br/>})</pre>                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   | `{}`                                                                             | no         |
| `cos`                                   | COS model, cloud, credential, and channel risk configuration                                                                                                                                      | <pre>object({<br/>  model      = optional(string, "cos")<br/>  cloud      = optional(string, "k8s")<br/>  credential = optional(string, "k8s")<br/>  risk       = optional(string, "stable")<br/>})</pre>                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                  | `{}`                                                                             | no         |
| `config_server`                         | MongoDB config-server application configuration                                                                                                                                                   | <pre>object({<br/>  app_name           = optional(string, "config-server")<br/>  base               = optional(string, "ubuntu@24.04")<br/>  channel            = optional(string, "8/stable")<br/>  config             = optional(map(string), { role = "config-server" })<br/>  constraints        = optional(string, "arch=amd64 cores=2 mem=8G")<br/>  endpoint_bindings  = optional(set(object({ space = string, endpoint = optional(string) })), [])<br/>  machines           = optional(set(string), null)<br/>  revision           = optional(number, null)<br/>  storage_directives = optional(map(string), {})<br/>  units              = optional(number, 1)<br/>})</pre>                                                             | `{}`                                                                             | no         |
| `mongos`                                | Mongos application configuration                                                                                                                                                                  | <pre>object({<br/>  app_name           = optional(string, "mongos")<br/>  base               = optional(string, "ubuntu@24.04")<br/>  channel            = optional(string, "8/stable")<br/>  config             = optional(map(string), {})<br/>  constraints        = optional(string, "arch=amd64")<br/>  endpoint_bindings  = optional(set(object({ space = string, endpoint = optional(string) })), [])<br/>  revision           = optional(number, null)<br/>  units              = optional(number, 1)<br/>})</pre>                                                                                                                                                                                                                                                                       | `{}`                                                                             | no         |
| `shards`                                | Shard application configurations (scalable list)                                                                                                                                                 | <pre>list(object({<br/>  app_name           = string<br/>  base               = optional(string, "ubuntu@24.04")<br/>  channel            = optional(string, "8/stable")<br/>  config             = optional(map(string), {})<br/>  constraints        = optional(string, "arch=amd64 cores=2 mem=8G")<br/>  endpoint_bindings  = optional(set(object({ space = string, endpoint = optional(string) })), [])<br/>  machines           = optional(set(string), null)<br/>  revision           = optional(number, null)<br/>  storage_directives = optional(map(string), {})<br/>  units              = optional(number, 3)<br/>}))</pre>                                                                                                                                     | `[{ app_name = "shard-one" }, { app_name = "shard-two" }]`                      | no         |
| `data_integrator`                       | Data-integrator application configuration                                                                                                                                                         | <pre>object({<br/>  app_name           = optional(string, "data-integrator")<br/>  base               = optional(string, "ubuntu@24.04")<br/>  channel            = optional(string, "latest/stable")<br/>  config             = optional(map(string), { database-name = "mongodb", extra-user-roles = "admin" })<br/>  constraints        = optional(string, "arch=amd64 cores=1 mem=2G")<br/>  endpoint_bindings  = optional(set(object({ space = string, endpoint = optional(string) })), [])<br/>  machines           = optional(set(string), null)<br/>  revision           = optional(number, null)<br/>  storage_directives = optional(map(string), {})<br/>  units              = optional(number, 1)<br/>})</pre>                                                                                                | `{}`                                                                             | no         |
| `s3_integrator`                         | Optional S3-compatible backup-integrator configuration                                                                                                                                            | <pre>object({<br/>  config      = map(string)<br/>  channel     = optional(string, "2/stable")<br/>  base        = optional(string, "ubuntu@24.04")<br/>  revision    = optional(number, null)<br/>  constraints = optional(string, "arch=amd64 cores=1 mem=2G")<br/>  machines    = optional(set(string), [])<br/>})</pre>                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 | `null`                                                                           | no         |
| `s3_access_key`                         | Optional access key for S3-compatible object storage                                                                                                                                               | `string` (sensitive)                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       | `null`                                                                           | no         |
| `s3_secret_key`                         | Optional secret key for S3-compatible object storage                                                                                                                                               | `string` (sensitive)                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       | `null`                                                                           | no         |
| `tls_client_private_key`                | Optional PEM private key for MongoDB client-to-server TLS                                                                                                                                         | `string` (sensitive)                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       | `null`                                                                           | no         |
| `tls_peer_private_key`                  | Optional PEM private key for MongoDB peer-to-peer TLS                                                                                                                                             | `string` (sensitive)                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       | `null`                                                                           | no         |
| `logging_config`                        | Logging configuration used by the MongoDB sharded-cluster module                                                                                                                                 | `string`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   | `"<root>=INFO"`                                                                  | no         |
| `self_signed_certificates`              | Self-signed-certificates application configuration                                                                                                                                                | <pre>object({<br/>  app_name    = optional(string, "self-signed-certificates")<br/>  channel     = optional(string, "1/stable")<br/>  revision    = optional(number, null)<br/>  base        = optional(string, "ubuntu@24.04")<br/>  constraints = optional(string, "arch=amd64 cores=1 mem=2G")<br/>  config      = optional(map(string), { ca-common-name = "MongoDB CA" })<br/>  units       = optional(number, 1)<br/>})</pre>                                                                                                                                                                                                                                                                                                                                                                                       | `{}`                                                                             | no         |
| `opentelemetry_collector`               | OpenTelemetry Collector subordinate application configuration                                                                                                                                     | <pre>object({<br/>  app_name = optional(string, "opentelemetry-collector")<br/>  channel  = optional(string, "2/stable")<br/>  revision = optional(number, null)<br/>  base     = optional(string, "ubuntu@24.04")<br/>  config   = optional(map(string), {})<br/>})</pre>                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 | `{}`                                                                             | no         |
| `etcd`                                  | Charmed etcd configuration for rolling operations                                                                                                                                                 | <pre>object({<br/>  app_name    = optional(string, "etcd")<br/>  channel     = optional(string, "3.6/stable")<br/>  units       = optional(number, 3)<br/>  constraints = optional(string, "arch=amd64 cores=2 mem=4G")<br/>  storage     = optional(map(string), { data = "10G" })<br/>})</pre>                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   | `{}`                                                                             | no         |
| `ldap_integration`                      | Optional existing LDAP offer; must be configured with `ldap_certificate_transfer_integration`                                                                                                    | `object({ url = string })`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 | `null`                                                                           | no         |
| `ldap_certificate_transfer_integration` | Optional existing LDAP certificate-transfer offer; must be configured with `ldap_integration`                                                                                                    | `object({ url = string })`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 | `null`                                                                           | no         |
| `vault_kv_integration`                  | Optional existing Vault KV offer for encryption at rest                                                                                                                                           | `object({ url = string })`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 | `null`                                                                           | no         |

## Outputs

| Name           | Description                                                              |
| -------------- | ------------------------------------------------------------------------ |
| `components`   | Map of all components deployed by the solution                           |
| `metadata`     | Metadata of the MongoDB sharded-cluster deployment                      |
| `models`       | Map keyed by model UUID containing the components deployed in each model |
| `offers`       | Map of offers exposed by the solution                                    |
| `shard_models` | Map of shard models created, keyed by shard index                       |

## Optional integrations

### LDAP

The module does not deploy LDAP. To integrate an LDAP deployment from another
model, provide both its `ldap` and `ldap-certificate-transfer` offer URLs:

```hcl
ldap_integration = {
  url = "admin/ldap.ldap"
}

ldap_certificate_transfer_integration = {
  url = "admin/ldap.send-ca-cert"
}
```

Both integrations must be configured together and must refer to an existing,
operational LDAP deployment.

### Encryption at rest

Enable encryption in the MongoDB configuration and provide the Vault KV offer:

```hcl
config_server = {
  config = {
    role                      = "config-server"
    enable-encryption-at-rest = "true"
  }
}

vault_kv_integration = {
  url = "admin/vault.vault-kv"
}
```

The module does not initialize, unseal, authorize, or configure Vault.

The offer must refer to an existing operational Vault deployment.
Follow the
[`vault` charm documentation](https://charmhub.io/vault/docs/h-initialize-vault)
to prepare it before applying this module.

### S3-compatible backups

The object-storage bucket or container must exist before deploying this
solution. The supplied credentials must be able to list it and read, create,
and delete objects under the configured path.

Configure the backup integrator with the endpoint exposed by your
S3-compatible storage service:

```hcl
s3_integrator = {
  config = {
    bucket   = "my-mongodb-backups"
    region   = "my-region"
    endpoint = "https://my-s3-compatible-endpoint.example.com"
    path     = "mongodb"
  }
}
```

Provide credentials using sensitive Terraform environment variables:

```bash
export TF_VAR_s3_access_key="<s3-access-key>"
export TF_VAR_s3_secret_key="<s3-secret-key>"
```

The exact endpoint, region, and addressing requirements depend on the selected
S3-compatible service.

### TLS certificates

The solution deploys `self-signed-certificates` as its default certificate
authority. This is intended for evaluation, use your organization's certificate
provider for production deployments.

Optional custom MongoDB client and peer TLS private keys can be supplied through
the sensitive `tls_client_private_key` and `tls_peer_private_key` variables.

## Deploy

The following diagram shows the components deployed by this solution and their
integrations across the Azure VM and Kubernetes models.

![Charmed MongoDB sharded cluster deployment](docs/sharded-cluster-azure-vm.excalidraw.svg)

Authenticate with Azure before initializing or applying the Terraform module:

```bash
az login
```

Initialize Terraform:

```bash
terraform init
```

Configure your Azure infrastructure reference using the remote state from your clouds/azure deployment:

Define `TF_VAR_remote_state` using the appropriate values. See
[`variables.tf`](variables.tf) for the default values.

```bash
export TF_VAR_remote_state='{
  "storage_account_name": "YOUR_STORAGE_ACCOUNT_NAME",
  "resource_group_name": "YOUR_RESOURCE_GROUP_NAME",
  "container_name": "tfstate",
  "key": "infra.terraform.tfstate"
}'
```

Terraform automatically loads exported variables prefixed with `TF_VAR_`, so
the value does not need to be passed separately with `-var`.

Initialize Terraform:

```bash
terraform init
```

Deploy:

```bash
terraform plan -out terraform.out
terraform apply terraform.out
```

## Advanced Configuration

### Model and Shard Configuration

This deployment supports scalable shards through dynamic model creation. All Juju model names are centrally configured in a `models` variable and matched by index to shard configurations.

#### Default Configuration (2 Shards)
```hcl
models = {
  config_server = "mongodb-config"
  shards = ["mongodb-shard-one", "mongodb-shard-two"]
}

shards = [
  { app_name = "shard-one" },    # → deployed in "mongodb-shard-one"
  { app_name = "shard-two" },    # → deployed in "mongodb-shard-two"
]
```

#### Custom Multi-Shard Configuration
```hcl
models = {
  config_server = "production-config"
  shards = [
    "primary-shard-model",
    "analytics-shard-model", 
    "cache-shard-model",
    "archive-shard-model"
  ]
}

shards = [
  {
    app_name    = "primary-shard"
    units       = 5
    constraints = "arch=amd64 cores=4 mem=8G"
  },
  {
    app_name    = "analytics-shard"
    units       = 3
    constraints = "arch=amd64 cores=2 mem=4G"
  },
  {
    app_name    = "cache-shard"
    units       = 3
    constraints = "arch=amd64 cores=2 mem=4G"
  },
  {
    app_name    = "archive-shard"
    units       = 1
    constraints = "arch=amd64 cores=1 mem=2G"
  }
]
```

#### Configuration Rules
- **Index matching**: `shards[i]` is deployed in `models.shards[i]`
- **Count validation**: Number of shard models must equal number of shards
- **Unique names**: All model names (config + shards) must be unique
- **Flexible naming**: Use any naming convention that fits your environment

### Observability Stack (COS)

The solution automatically deploys COS Lite for monitoring, logging, and alerting capabilities.
MongoDB observability is provided through OpenTelemetry Collectors that are **always deployed** 
and automatically configured in every model.

**OpenTelemetry Collector Configuration:**
```hcl
opentelemetry_collector = {
  app_name = "opentelemetry-collector"
  channel  = "2/stable"
  config   = {}
}
```

**COS Storage Configuration:**
The default storage directives are intended only for testing. Size every volume
for expected retention and ingestion volume before production deployment:

```hcl
cos = {
  grafana_storage_directives = {
    database = "20G"
  }
  loki_storage_directives = {
    active-index-directory = "20G"
    loki-chunks             = "100G"
  }
  prometheus_storage_directives = {
    database = "100G"
  }
}
```

### Rolling Operations and etcd Configuration

This deployment includes Charmed etcd for rolling operations support, enabling zero-downtime maintenance and coordinated rolling restarts across shards. The etcd deployment runs in the "mongodb-etcd" model with automatic TLS and integrates with all MongoDB components via cross-model offers.

The etcd cluster is automatically configured with minimal setup:

```hcl
etcd = {
  app_name    = "etcd"
  channel     = "3.6/stable"
  units       = 3  # Use odd numbers (3, 5, 7) for high availability
  constraints = "arch=amd64 cores=2 mem=4G"
  storage = {
    data = "10G"  # Adjust based on expected cluster size and retention
  }
}
```

The etcd TLS certificates are automatically managed by the product module with hardcoded settings:
- Channel: `1/stable`
- CA Common Name: `Etcd CA`
- No additional configuration required

For production deployments, consider:
- Using at least 3 etcd units for high availability
- Sizing storage based on cluster size and retention requirements
- Placing etcd units across different availability zones
