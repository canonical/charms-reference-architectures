# Terraform module for MongoDB Sharded Cluster on Kubernetes

This Terraform root module facilitates the deployment of a Charmed MongoDB
sharded cluster on Kubernetes using the
[Terraform Juju provider](https://github.com/juju/terraform-provider-juju/).
For more information, refer to the provider
[documentation](https://registry.terraform.io/providers/juju/juju/latest/docs).

The solution deploys a MongoDB sharded cluster with config server, mongos, 
multiple shards, data integrator, TLS certificates, and COS Lite. It can
also integrate with existing LDAP and Vault deployments and an optional S3
integrator for backups.

The deployment uses a scalable number of Kubernetes models:

- The config-server model contains the config server, mongos, data integrator,
  optional S3 integrator, and self-signed-certificates for MongoDB TLS.
- Dynamic shard models: Each shard is deployed in its own model with either 
  custom names or auto-generated names (mongodb-shard-1, mongodb-shard-2, etc.)
- Cross-model certificate integration: The self-signed-certificates application
  in the config-server model provides TLS certificates to all shards via offers.

## Requirements

| Name          | Version         |
| ------------- | --------------- |
| Terraform     | >= 1.11         |
| Juju provider | >= 2.2.1, < 3.0 |
| Juju          | 3.6 or later    |

The Kubernetes cluster must already be registered as a Juju cloud. By
default, both the MongoDB and COS models use a cloud and credential named
`k8s`. Override `model_config` and `cos` when the registered names differ.

The Juju provider can be configured with `JUJU_CONTROLLER_ADDRESSES`,
`JUJU_USERNAME`, and `JUJU_PASSWORD`.

## Providers

| Name   | Version         |
| ------ | --------------- |
| `juju` | >= 2.2.1, < 3.0 |

## Modules

| Name                       | Source                                                                         |
| -------------------------- | ------------------------------------------------------------------------------ |
| `mongodb_sharded_cluster`  | `canonical/mongodb-k8s-operator//terraform/product/sharded_cluster` (`8/edge`) |
| `cos`                      | `canonical/observability-stack//terraform/cos-lite` (`tf-cos-lite-3.0.2`)      |
| `self_signed_certificates` | `canonical/self-signed-certificates-operator//terraform` (`main`)              |

## Resources

| Name                        | Type                                                                                                    |
| --------------------------- | ------------------------------------------------------------------------------------------------------- |
| `juju_model.config_server`  | [Juju model](https://registry.terraform.io/providers/juju/juju/latest/docs/resources/model)             |
| `juju_model.shards`         | [Juju model](https://registry.terraform.io/providers/juju/juju/latest/docs/resources/model)             |
| `juju_offer.certificates`   | [Juju offer](https://registry.terraform.io/providers/juju/juju/latest/docs/resources/offer)             |

Applications, integrations, offers, secrets, and COS resources are managed by
the child modules listed above.

## Inputs

| Name                                              | Description                                                                                                                                                                                       | Type                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       | Default                                                                          | Required   |
| ------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------- | :--------: |
| `model_config`                                    | Configuration for Kubernetes models                                                                                                                                                               | <pre>object({<br/>  cloud      = optional(string, "k8s")<br/>  credential = optional(string, "k8s")<br/>})</pre>                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           | `{}`                                                                             | no         |
| `models`                                          | Centralized model names for config-server and shards                                                                                                                                              | <pre>object({<br/>  config_server = optional(string, "mongodb-config")<br/>  shards        = optional(list(string), ["mongodb-shard-one", "mongodb-shard-two"])<br/>})</pre>                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                               | `{}`                                                                             | no         |
| `cos`                                             | COS model, cloud, credential, and channel risk configuration                                                                                                                                      | <pre>object({<br/>  model_name                    = optional(string, "cos")<br/>  cloud                         = optional(string, "k8s")<br/>  credential                    = optional(string, "k8s")<br/>  risk                          = optional(string, "stable")<br/>  grafana_storage_directives    = optional(map(string), { database = "1G" })<br/>  loki_storage_directives       = optional(map(string), { active-index-directory = "1G", loki-chunks = "1G" })<br/>  prometheus_storage_directives = optional(map(string), { database = "1G" })<br/>})</pre>                                                                                                                                                                                                                                 | `{}`                                                                             | no         |
| `config_server`                                   | MongoDB config-server application configuration                                                                                                                                                   | <pre>object({<br/>  app_name           = optional(string, "config-server")<br/>  base               = optional(string, "ubuntu@24.04")<br/>  channel            = optional(string, "8/stable")<br/>  config             = optional(map(string), { role = "config-server" })<br/>  constraints        = optional(string, "arch=amd64")<br/>  endpoint_bindings  = optional(set(object({ space = string, endpoint = optional(string) })), [])<br/>  machines           = optional(set(string), null)<br/>  revision           = optional(number, null)<br/>  storage_directives = optional(map(string), {})<br/>  units              = optional(number, 1)<br/>})</pre>                                                                                                                                      | `{}`                                                                             | no         |
| `mongos`                                          | Mongos application configuration                                                                                                                                                                  | <pre>object({<br/>  app_name           = optional(string, "mongos")<br/>  base               = optional(string, "ubuntu@24.04")<br/>  channel            = optional(string, "8/stable")<br/>  config             = optional(map(string), {})<br/>  constraints        = optional(string, "arch=amd64")<br/>  endpoint_bindings  = optional(set(object({ space = string, endpoint = optional(string) })), [])<br/>  revision           = optional(number, null)<br/>  units              = optional(number, 1)<br/>})</pre>                                                                                                                                                                                                                                                                                 | `{}`                                                                             | no         |
| `shards`                                          | Shard application configurations (scalable list)                                                                                                                                                  | <pre>list(object({<br/>  app_name           = string<br/>  base               = optional(string, "ubuntu@24.04")<br/>  channel            = optional(string, "8/stable")<br/>  config             = optional(map(string), {})<br/>  constraints        = optional(string, "arch=amd64")<br/>  endpoint_bindings  = optional(set(object({ space = string, endpoint = optional(string) })), [])<br/>  machines           = optional(set(string), null)<br/>  revision           = optional(number, null)<br/>  storage_directives = optional(map(string), {})<br/>  units              = optional(number, 3)<br/>}))</pre>                                                                                                                                                                                   | `[{ app_name = "shard-one" }, { app_name = "shard-two" }]`                       | no         |
| `data_integrator`                                 | Data-integrator application configuration                                                                                                                                                         | <pre>object({<br/>  app_name           = optional(string, "data-integrator")<br/>  base               = optional(string, "ubuntu@24.04")<br/>  channel            = optional(string, "latest/stable")<br/>  config             = optional(map(string), { database-name = "mongodb", extra-user-roles = "admin" })<br/>  constraints        = optional(string, "arch=amd64")<br/>  endpoint_bindings  = optional(set(object({ space = string, endpoint = optional(string) })), [])<br/>  machines           = optional(set(string), null)<br/>  revision           = optional(number, null)<br/>  storage_directives = optional(map(string), {})<br/>  units              = optional(number, 1)<br/>})</pre>                                                                                                | `{}`                                                                             | no         |
| `s3_integrator`                                   | Optional S3 backup-integrator configuration                                                                                                                                                       | <pre>object({<br/>  config      = map(string)<br/>  channel     = optional(string, "2/stable")<br/>  base        = optional(string, "ubuntu@24.04")<br/>  revision    = optional(number, null)<br/>  constraints = optional(string, "arch=amd64")<br/>  machines    = optional(set(string), [])<br/>})</pre>                                                                                                                                                                                                                                                                                                                                                                                                                                                                                               | `null`                                                                           | no         |
| `s3_access_key`                                   | Optional S3 access key                                                                                                                                                                            | `string` (sensitive, ephemeral)                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            | `null`                                                                           | no         |
| `s3_secret_key`                                   | Optional S3 secret key                                                                                                                                                                            | `string` (sensitive, ephemeral)                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            | `null`                                                                           | no         |
| `config_server_tls_client_private_key`            | Optional PEM private key for MongoDB client-to-server TLS                                                                                                                                         | `string` (sensitive, ephemeral)                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            | `null`                                                                           | no         |
| `config_server_tls_peer_private_key`              | Optional PEM private key for MongoDB peer-to-peer TLS                                                                                                                                             | `string` (sensitive, ephemeral)                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            | `null`                                                                           | no         |
| `logging_config`                                  | Logging configuration used by the MongoDB sharded-cluster module                                                                                                                                  | `string`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   | `"<root>=INFO"`                                                                  | no         |
| `self_signed_certificates`                        | Self-signed-certificates application configuration                                                                                                                                                | <pre>object({<br/>  app_name    = optional(string, "self-signed-certificates")<br/>  channel     = optional(string, "1/stable")<br/>  revision    = optional(number, null)<br/>  base        = optional(string, "ubuntu@24.04")<br/>  constraints = optional(string, "arch=amd64")<br/>  config      = optional(map(string), { ca-common-name = "MongoDB CA" })<br/>  units       = optional(number, 1)<br/>})</pre>                                                                                                                                                                                                                                                                                                                                                                                       | `{}`                                                                             | no         |
| `ldap_integration`                                | Optional existing LDAP offer; must be configured with `ldap_certificate_transfer_integration`                                                                                                     | `object({ url = string })`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 | `null`                                                                           | no         |
| `ldap_certificate_transfer_integration`           | Optional existing LDAP certificate-transfer offer; must be configured with `ldap_integration`                                                                                                     | `object({ url = string })`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 | `null`                                                                           | no         |
| `vault_kv_integration`                            | Optional existing Vault KV offer for encryption at rest                                                                                                                                           | `object({ url = string })`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 | `null`                                                                           | no         |
| `s3_secret_version`                               | 0 creates no secret; 1 creates it; increment to rotate. Ignored when `s3_secret_uri` is set.                                                                                                      | `number`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   | `0`                                                                              | no         |
| `s3_secret_uri`                                   | Existing secret URI in the consuming application model; overrides credentials and version.                                                                                                        | `string`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   | `null`                                                                           | no         |
| `config_server_tls_client_private_key_version`    | 0 creates no secret; 1 creates it; increment to rotate. Ignored when `config_server_tls_client_private_key_secret_uri` is set.                                                                    | `number`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   | `0`                                                                              | no         |
| `config_server_tls_client_private_key_secret_uri` | Existing secret URI in the consuming application model; overrides credentials and version.                                                                                                        | `string`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   | `null`                                                                           | no         |
| `config_server_tls_peer_private_key_version`      | 0 creates no secret; 1 creates it; increment to rotate. Ignored when `config_server_tls_peer_private_key_secret_uri` is set.                                                                      | `number`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   | `0`                                                                              | no         |
| `config_server_tls_peer_private_key_secret_uri`   | Existing secret URI in the consuming application model; overrides credentials and version.                                                                                                        | `string`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   | `null`                                                                           | no         |

## Outputs

| Name           | Description                                                              |
| -------------- | ------------------------------------------------------------------------ |
| `components`   | Map of all components deployed by the solution                           |
| `metadata`     | Metadata of the MongoDB sharded-cluster deployment                       |
| `models`       | Map keyed by model UUID containing the components deployed in each model |
| `offers`       | Map of offers exposed by the solution                                    |
| `shard_models` | Map of shard models created, keyed by shard index                        |

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

### S3 backups

The S3 bucket must exist before deploying this solution. The AWS identity used
by the backup integrator must be able to list the bucket and read, create, and
delete objects under the configured path.

Add the backup integrator configuration to `terraform.tfvars`:

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

The configuration fields are:

- `bucket`: name of the existing S3 bucket.
- `region`: AWS region containing the bucket.
- `endpoint`: S3 API endpoint for the selected region.
- `path`: optional prefix under which MongoDB backups are stored.

Provide the S3 credentials through sensitive Terraform environment variables
instead of writing them to `terraform.tfvars`:

```bash
export TF_VAR_s3_access_key="<s3-access-key>"
export TF_VAR_s3_secret_key="<s3-secret-key>"
```

### TLS certificates

The solution deploys `self-signed-certificates` as its default certificate
authority. This is intended for evaluation, use your organization's certificate
provider for production deployments.

Optional custom MongoDB client and peer TLS private keys can be supplied through
the sensitive `config_server_tls_client_private_key` and `config_server_tls_peer_private_key` variables.

## Deploy

The following diagram shows the components deployed by this solution and their
integrations across the Kubernetes models.

![Charmed MongoDB sharded cluster deployment](docs/sharded-cluster-aws-k8s.excalidraw.svg)

If the Kubernetes cloud is not registered in Juju as `k8s`, configure its
registered cloud and credential names:

```hcl
model_config = {
  cloud      = "my-k8s"
  credential = "my-k8s"
}

cos = {
  cloud      = "my-k8s"
  credential = "my-k8s"
}
```

The default COS storage directives explicitly allocate 1 GiB to Grafana and
Prometheus, and 1 GiB to each of Loki's two volumes. These small defaults are
intended only for local testing. Size every volume for the expected retention
and ingestion volume before production deployment:

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

Initialize Terraform:

```bash
terraform init
```

Plan and apply the solution:

```bash
terraform plan \
  -out terraform.out
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
MongoDB observability is provided through direct integrations with COS components.

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

## Sensitive configurations and secrets

Credential inputs are sensitive and ephemeral. These solution modules forward credentials, versions, and optional existing-secret URIs to the MongoDB product module, which creates Juju secrets using write-only `value_wo` values. Credentials are omitted from state and saved plans. Terraform requires version 1.11 or later and Juju provider 2.2.1 or later.

| Credential inputs                      | Version input                                  | Existing secret URI input                         | Secret keys                |
| -------------------------------------- | ---------------------------------------------- | ------------------------------------------------- | -------------------------- |
| `config_server_tls_client_private_key` | `config_server_tls_client_private_key_version` | `config_server_tls_client_private_key_secret_uri` | `private-key` (PEM)        |
| `config_server_tls_peer_private_key`   | `config_server_tls_peer_private_key_version`   | `config_server_tls_peer_private_key_secret_uri`   | `private-key` (PEM)        |
| `s3_access_key`, `s3_secret_key`       | `s3_secret_version`                            | `s3_secret_uri`                                   | `access-key`, `secret-key` |

A version of `0` creates no managed secret. Set it to `1` and supply the credential to create the secret. Change the credential and increment the version to rotate it in place. Both S3 keys share one secret and version. An unchanged version permits unrelated plans and applies with credentials unset; changing a credential alone does not rotate it. Setting the version back to `0` removes the managed secret and grant when no existing URI is supplied.

Keep version numbers in non-sensitive configuration, for example:

```hcl
config_server_tls_client_private_key_version = 1
# Enable s3_integrator before setting s3_secret_version = 1.
```

Supply credentials through environment variables at both plan and apply:

```bash
export TF_VAR_config_server_tls_client_private_key="$(cat client-tls.key)"
terraform plan -out=tfplan
terraform apply tfplan
```

Use the same pattern for the peer key and S3 credentials. Keep credentials out of `.tfvars` files. Passing credentials through `-var` may expose them in shell history. If another root module calls this solution, declare its forwarded credential variables with both `sensitive = true` and `ephemeral = true`.

An existing-secret URI takes priority over credentials and version. The product module skips secret creation, passes the URI to charm config, and grants the consuming application access. The secret must already exist in that application's model and contain the keys listed above. Both `secret:<id>` and `secret://<model-uuid>/<id>` are supported. S3 secrets are used only when `s3_integrator` is configured. These solutions create their models, so an existing secret must be created in the appropriate solution model before switching its input to URI mode.

When switching from a managed secret to a URI, use a separate existing secret: Terraform destroys the previously managed secret. Credentials previously stored by older product modules remain in historical state and saved plans; rotate them. Existing deployments must explicitly set the appropriate version and supply credentials when migrating. Sharded-cluster callers must also rename the old TLS inputs and their TF_VAR_ environment variables to the config_server_ names above. TLS inputs apply only to the config server.

The referenced MongoDB product module must include the new version and URI inputs. Deploy these solution changes after the corresponding product-module changes are available at the referenced revision.
