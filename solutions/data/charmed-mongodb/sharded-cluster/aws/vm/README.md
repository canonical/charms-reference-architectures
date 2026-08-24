# Terraform module for a Charmed MongoDB sharded cluster on AWS VMs

This Terraform root module deploys a MongoDB sharded cluster with the
[Terraform Juju provider](https://github.com/juju/terraform-provider-juju/).
It uses the MongoDB operator's `terraform/product/sharded_cluster` module.

The deployment uses a scalable number of AWS models:

- The config-server model contains the config server, mongos, data integrator,
  optional S3 integrator, and self-signed-certificates for MongoDB TLS.
- Dynamic shard models: Each shard is deployed in its own model with either 
  custom names or auto-generated names (mongodb-shard-1, mongodb-shard-2, etc.)
- The mongodb-etcd model (hardcoded name) contains charmed etcd with its own 
  self-signed-certificates for rolling operations.

The MongoDB certificate and etcd endpoints are offered from their respective models so
the product module can integrate all remote shards regardless of count. The etcd 
deployment uses the charmed-etcd product module with automatic TLS configuration, 
while MongoDB uses the self-signed-certificates in the config-server model.

The solution includes built-in observability with COS Lite (Canonical Observability Stack)
and OpenTelemetry Collectors providing monitoring, logging, and alerting capabilities. 
It also supports optional LDAP integration for authentication and Vault integration 
for encryption at rest.

## Requirements

| Name | Version |
|------|---------|
| Terraform | >= 1.6 |
| Juju provider | ~> 2.0 (compatible with etcd module >= 1.0 requirement) |

An AWS cloud and credential must be configured in Juju. Provider credentials
can be supplied with `JUJU_CONTROLLER_ADDRESSES`, `JUJU_USERNAME`, and
`JUJU_PASSWORD`.

## Modules

| Name | Source |
|------|--------|
| `mongodb_sharded_cluster` | `canonical/mongodb-operator//terraform/product/sharded_cluster` (`8/edge`) |
| `charmed_etcd` | `canonical/charmed-etcd-operator//terraform/charm` (`DPE-10183-tf-requirements`) |
| `cos` | `canonical/observability-stack//terraform/cos-lite` (`tf-cos-lite-3.0.2`) |

## Resources

| Name | Type |
|------|------|
| `juju_model.config_server` | Juju model |
| `juju_model.shards` | Dynamic shard models (for_each) |
| `juju_model.etcd` | Juju model (hardcoded "mongodb-etcd") |
| `module.charmed_etcd` | Charmed etcd product module |
| `module.self_signed_certificates` | MongoDB self-signed certificates module |
| `juju_offer.certificates` | MongoDB certificates offer |
| `juju_offer.etcd` | Etcd offer |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| `model_config` | Configuration for AWS models | `object` | `{ cloud = "aws", credential = null }` | no |
| `models` | Centralized model names for config-server and shards | `object` | `{}` | no |
| `cos` | COS configuration and storage directives | `object` | `{}` | no |
| `config_server` | MongoDB config-server application configuration | `object` | `{}` | no |
| `mongos` | Mongos application configuration | `object` | `{}` | no |
| `shards` | Shard application configurations (scalable list) | `list(object)` | `[{ app_name = "shard-one" }, { app_name = "shard-two" }]` | no |
| `data_integrator` | Data-integrator configuration | `object` | `{}` | no |
| `s3_integrator` | Optional S3 integrator configuration | `object` | `null` | no |
| `opentelemetry_collector` | OpenTelemetry Collector configuration (always deployed) | `object` | `{}` | no |
| `etcd` | Charmed etcd configuration for rolling operations | `object` | `{}` | no |
| `self_signed_certificates` | Self-signed certificates for MongoDB TLS | `object` | `{}` | no |
| `ldap_integration` | Optional existing LDAP offer | `object` | `null` | no |
| `ldap_certificate_transfer_integration` | Optional existing LDAP certificate transfer offer | `object` | `null` | no |
| `vault_kv_integration` | Optional existing Vault KV offer | `object` | `null` | no |
| `s3_access_key` | Optional S3 access key | `string` (sensitive) | `null` | no |
| `s3_secret_key` | Optional S3 secret key | `string` (sensitive) | `null` | no |
| `tls_client_private_key` | Optional config-server client TLS private key | `string` (sensitive) | `null` | no |
| `tls_peer_private_key` | Optional config-server peer TLS private key | `string` (sensitive) | `null` | no |
| `logging_config` | MongoDB product-module logging configuration | `string` | `"<root>=INFO"` | no |

## Outputs

| Name | Description |
|------|-------------|
| `components` | Map of all deployed components including COS |
| `metadata` | Sharded-cluster deployment metadata |
| `models` | Map keyed by model UUID with components deployed in each model |
| `offers` | Map of offers exposed by the solution including COS offers |
| `shard_models` | Map of shard models created, keyed by shard index |

## Rolling Operations Support

This deployment includes Charmed etcd deployed using the etcd product module for rolling operations support, which enables:

- Zero-downtime cluster maintenance operations
- Coordinated rolling restarts across shards
- Safe configuration updates without service interruption
- Improved cluster resilience during updates

The etcd deployment features:
- **Hardcoded model**: Etcd runs in the "mongodb-etcd" Juju model
- **Streamlined deployment**: Uses etcd charm module (etcd + self-signed certificates only) instead of the full product module, avoiding unnecessary components like additional grafana agents and data integrators since observability is handled by the dedicated OpenTelemetry Collectors
- **Automatic TLS**: Built-in self-signed certificates with "Etcd CA" common name
- **Cross-model integration**: Etcd client endpoint offered to MongoDB config servers and shards
- **Production-ready**: 3-unit HA cluster by default

MongoDB uses the self-signed-certificates deployed in the config-server model for its TLS needs, ensuring proper certificate separation between etcd and MongoDB components.

## Centralized Model Configuration

All Juju model names are configured in a centralized `models` variable, making it easy to manage and ensuring consistency across the deployment.

### Model Structure
```hcl
models = {
  config_server = "mongodb-config"        # Config server model name
  shards = [                              # Shard model names (matched by index)
    "mongodb-shard-one",                  # → shard[0]
    "mongodb-shard-two",                  # → shard[1]
    "analytics-shard",                    # → shard[2]
    "cache-shard"                         # → shard[3]
  ]
}

shards = [
  { app_name = "primary-shard" },         # Deployed in "mongodb-shard-one"
  { app_name = "secondary-shard" },       # Deployed in "mongodb-shard-two"  
  { app_name = "analytics-shard" },       # Deployed in "analytics-shard"
  { app_name = "cache-shard" }            # Deployed in "cache-shard"
]
```

### Key Benefits
- **Centralized**: All model names defined in one place
- **Flexible**: Use any naming convention that fits your environment
- **Validated**: Ensures model names are unique and counts match
- **Clear mapping**: Index-based mapping between shards and models

## Scalable Shard Configuration

This deployment supports any number of shards through dynamic model creation. Model names are centrally configured and matched by index to shard configurations.

### Default Configuration (2 Shards)
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

### Custom Multi-Shard Configuration
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

### Model Mapping Rules
- **Index matching**: `shards[i]` is deployed in `models.shards[i]`
- **Count validation**: Number of shard models must equal number of shards
- **Unique names**: All model names (config + shards) must be unique
- **Flexible naming**: Use any naming convention that fits your environment

## Deploy

The default configuration creates the config-server, etcd, and shard models 
dynamically based on the number of shards configured, then deploys the 
sharded cluster with etcd-powered rolling operations and **mandatory observability**:

```bash
terraform init
terraform plan -out terraform.out
terraform apply terraform.out
```

## Optional integrations

### Observability Stack (COS)

The solution automatically deploys COS Lite for monitoring, logging, and alerting capabilities.
MongoDB observability is provided through OpenTelemetry Collectors that are **always deployed** 
and automatically configured in every model.

**OpenTelemetry Collector Configuration:**
```hcl
opentelemetry_collector = {
  app_name = "opentelemetry-collector"
  channel  = "2/stable"
  constraints = "arch=amd64 cores=1 mem=2G"  # Optional
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

**Architecture:**
- OpenTelemetry Collectors are **mandatory** and deployed in each model (config-server + all shard models)
- Collectors automatically integrate with COS stack for metrics, logs, and dashboards
- MongoDB applications automatically connect to OpenTelemetry Collectors via `cos_agent_integrations`
- No toggle required - observability is built-in and always available

### LDAP Integration

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

### Rolling Operations and etcd Configuration

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

### S3 backups

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

Provide the S3 credentials through sensitive environment variables:

```bash
export TF_VAR_s3_access_key="<s3-access-key>"
export TF_VAR_s3_secret_key="<s3-secret-key>"
```
