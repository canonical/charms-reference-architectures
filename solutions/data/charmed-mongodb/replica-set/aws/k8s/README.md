# Charmed MongoDB replica set on AWS Kubernetes

This Terraform root module deploys a Charmed MongoDB replica set with the
`mongodb-k8s` charm on a Kubernetes cluster running on AWS. It uses the
[Terraform Juju provider](https://github.com/juju/terraform-provider-juju/).

The solution includes a data integrator, TLS certificates, and COS Lite. It can
also integrate with existing LDAP and Vault deployments and deploy an optional
S3 integrator for backups.

## Requirements

| Name | Version |
| --- | --- |
| Terraform | >= 1.6 |
| Juju provider | ~> 2.0 |
| Juju | 3.6 or later |

The AWS Kubernetes cluster must already be registered as a Juju cloud. By
default, both the MongoDB and COS models use a cloud and credential named
`k8s`. Override `mongodb_model` and `cos` when the registered names differ.

The Juju provider can be configured with `JUJU_CONTROLLER_ADDRESSES`,
`JUJU_USERNAME`, and `JUJU_PASSWORD`.

## Modules

| Name | Source |
| --- | --- |
| `mongodb_replica_set` | `canonical/mongodb-k8s-operator//terraform/product/replica_set` (`8/edge`) |
| `cos` | `canonical/observability-stack//terraform/cos-lite` (`tf-cos-lite-3.0.2`) |
| `self_signed_certificates` | `canonical/self-signed-certificates-operator//terraform` (`main`) |

## Main inputs

| Name | Description | Default |
| --- | --- | --- |
| `mongodb_model` | MongoDB Kubernetes model name, cloud, and credential | `{}` (`mongodb`, `k8s`, `k8s`) |
| `cos` | COS model name, cloud, credential, and risk | `{}` (`cos`, `k8s`, `k8s`, `stable`) |
| `mongodb` | `mongodb-k8s` application configuration | `{}` |
| `data_integrator` | Data-integrator application configuration | `{}` |
| `s3_integrator` | Optional S3 backup-integrator configuration | `null` |
| `self_signed_certificates` | Certificate provider configuration | `{}` |
| `ldap_integration` | Optional existing LDAP offer | `null` |
| `ldap_certificate_transfer_integration` | Optional LDAP certificate-transfer offer | `null` |
| `vault_kv_integration` | Optional Vault KV offer for encryption at rest | `null` |

See [variables.tf](variables.tf) for the complete input types and defaults.

## Outputs

| Name | Description |
| --- | --- |
| `components` | All applications deployed by the solution |
| `metadata` | MongoDB replica-set deployment metadata |
| `models` | Components grouped by Juju model UUID |
| `offers` | Offers exposed by the MongoDB product module |

## Optional integrations

### LDAP

Provide both offer URLs together:

```hcl
ldap_integration = {
  url = "admin/ldap.ldap"
}

ldap_certificate_transfer_integration = {
  url = "admin/ldap.send-ca-cert"
}
```

### Encryption at rest

Enable encryption in the MongoDB configuration and provide the Vault KV offer:

```hcl
mongodb = {
  config = {
    role                        = "replication"
    enable-encryption-at-rest   = "true"
  }
}

vault_kv_integration = {
  url = "admin/vault.vault-kv"
}
```

The module does not initialize, unseal, authorize, or configure Vault.

### S3 backups

The bucket must exist before deployment. Configure the integrator in
`terraform.tfvars`:

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

Provide credentials using sensitive Terraform environment variables:

```bash
export TF_VAR_s3_access_key="<s3-access-key>"
export TF_VAR_s3_secret_key="<s3-secret-key>"
```

### TLS certificates

The solution deploys `self-signed-certificates` by default. This is suitable
for evaluation; use your organization's certificate provider in production.
Custom client and peer private keys can be supplied through
`tls_client_private_key` and `tls_peer_private_key`.

## Deploy

If the AWS Kubernetes cloud is not registered in Juju as `k8s`, configure its
registered cloud and credential names:

```hcl
mongodb_model = {
  cloud      = "my-eks"
  credential = "my-eks"
}

cos = {
  cloud      = "my-eks"
  credential = "my-eks"
}
```

Initialize, review, and apply the deployment:

```bash
terraform init
terraform plan -out terraform.out
terraform apply terraform.out
```
