# OpenSearch large deployment on Azure machines with OpenSearch Dashboards, TLS, COS Lite and Azure Storage backups

Solution module that composes the
[OpenSearch machine large deployment product module](https://github.com/canonical/opensearch-operator/tree/2/edge/terraform/machine/product/large_deployment)
into a complete stack on Azure virtual machines. You provide a Kubernetes cloud for COS Lite, and
optionally an Azure storage container for backups, and the module handles the rest.

A large deployment is one OpenSearch cluster made of several OpenSearch
applications, where each application can have its own roles:

- `main`: the main orchestrator.
- `failover`: the failover orchestrator.
- `apps`: the other applications, for example data nodes.

## Deployed stack

- Model `cos` on `cos.cloud` (set `cos.model` to rename it):
  [COS Lite](https://github.com/canonical/observability-stack/tree/tf-cos-lite-3.0.3/terraform/cos-lite),
  which offers Prometheus remote-write, Loki logging and Grafana dashboards.
- Model `opensearch` on the controller's default cloud (set `opensearch_model`
  to rename it):
  - OpenSearch `main` and `failover` (with `cluster_manager` role) and one app in
    `apps`, `data` (with `data` role), 3 units each. The product module also
    deploys OpenSearch Dashboards (3 units), `data-integrator` and
    `self-signed-certificates`.
  - The `opentelemetry-collector` subordinate on each OpenSearch and OpenSearch Dashboards
    machine, which forwards metrics, logs and dashboards to the COS Lite
    offers.
  - With `backups` set, `azure-storage-integrator` pointed at your container.
- Each model in `extra_models`: the OpenSearch apps you place
  there, and its own `opentelemetry-collector`.
- An internal Azure Load Balancer for the OpenSearch Dashboards
  machines. With `dashboards_load_balancer.dns_name`, also a DNS name for it that
  resolves inside the VNet. With `dashboards_load_balancer.key_vault_secret_id`,
  an Application Gateway replaces the Load Balancer (see
  [Using your own certificate](#using-your-own-certificate)).

Set `cos = null` to deploy without COS Lite and the collectors. No Kubernetes
cloud is then needed. Set `dashboards_load_balancer = null` to skip the load
balancer.

## Requirements

| Name      | Version  |
| --------- | -------- |
| terraform | >= 1.12  |
| juju      | ~> 2.3   |
| azurerm   | ~> 4.75  |

The controller needs the Azure machine cloud as its default cloud, and a
Kubernetes cloud for COS Lite (`juju add-k8s`).

The defaults match this repository's `clouds/azure` module: resource group
`main-rg`, VNet `main-vnet` with subnet `deployments-subnet`, and `10.0.0.0/8`
for the `allowed_cidrs` of each app. For another network,
set `network` (as `<resource group>/<VNet>`), `dashboards_load_balancer.subnet`,
and the `allowed_cidrs`. `dashboards_load_balancer.subnet_cidr` must be free in that VNet.
With `clouds/azure`, COS Lite's internal load balancer on AKS needs
`AKS_SUBNET_NETWORK_CONTRIBUTOR=true`.

The module reads credentials from the environment:

- Juju: the Juju CLI's current controller, or the `JUJU_*` variables.
- Azure: the Azure CLI login (`az login`) or the `ARM_*` variables.
  `ARM_SUBSCRIPTION_ID` picks the subscription. The identity needs permission
  to manage load balancers, subnets and private DNS zones in the resource group
  of `network`. With `key_vault_secret_id`, it
  also needs to manage Application Gateways and to assign the gateway's identity.
  Public access also needs permission to manage public IPs and network security groups.

When an app in `apps` has the `cluster_manager` role, the product module waits for
`failover` with a script that runs `juju` and `jq` on the machine running Terraform,
against the Juju CLI's current controller.

The storage account key is an ephemeral input. Terraform does not store it in
the plan or the state. The product module hands it to `azure-storage-integrator`
through a Juju secret.

## Usage

```bash
export ARM_SUBSCRIPTION_ID=<subscription id>
terraform init
terraform apply
```

With backups, pass an existing storage account and container, and the account's key:

```bash
export TF_VAR_azure_storage_secret_key=<storage account key>
terraform apply -var 'backups={storage_account="myopensearchbackups", container="opensearch-backups"}'
```

The COS model uses the controller credential named like `cos.cloud`, which is
the name `juju add-k8s` gives it. If yours differs, set `cos.credential`.

### Getting credentials

```bash
# Client credentials: endpoints, user, password, index and CA.
juju run data-integrator/leader get-credentials -m opensearch

# admin password
juju run main/leader get-password -m opensearch

# OpenSearch Dashboards URL.
terraform output dashboards_load_balancer

# Grafana admin password.
juju run grafana/leader get-admin-password -m cos
```

### Choosing the OpenSearch apps

Set `apps` to the applications you need:

```hcl
apps = [
  {
    app_name    = "data-hot"
    config      = { roles = "data.hot" }
    constraints = "cores=8 mem=32G"
  },
  { app_name = "data-cold", config = { roles = "data.cold" }, units = 5 },
]
opensearch_charm = { profile = "production" }
```

- At least one app needs a `data` role.
- An app with the `cluster_manager` role needs `failover` (unset `roles` defaults to
  all roles, including `cluster_manager`).
- Choose `constraints` before the first apply.
  Changing it later replaces the application.

### Connecting an application

`get-credentials` returns a user and an index for one application.
The endpoints are the private addresses of all OpenSearch units.
Each app accepts connections from its `allowed_cidrs` (`clouds/azure` VNet by default).
With the `tls-ca` value saved in `ca.pem`:

```bash
curl --cacert ca.pem -u "<username>:<password>" "https://<endpoint>/<index>/_search?q=*"
```

Charms in the `opensearch` model can integrate with the `main`
`opensearch-client` endpoint instead.

### Opening OpenSearch Dashboards

Open the `url` from `terraform output dashboards_load_balancer` and log in as
`admin`, with the password from `juju run main/leader get-password -m opensearch`.

- By default, the internal Azure Load Balancer spreads requests over the
  OpenSearch Dashboards units.
- `dashboards_load_balancer.dns_name`: a name for OpenSearch Dashboards that
  resolves inside the VNet, for example `dashboards.example.internal`.
- `dashboards_load_balancer.key_vault_secret_id` and `key_vault_identity_id`:
  serve OpenSearch Dashboards with your own certificate from Key Vault. See [Using your own certificate](#using-your-own-certificate).
- `opensearch_dashboards.tls = false`: turns off TLS on OpenSearch Dashboards.
  Without the gateway, traffic is then unencrypted. With the gateway, it is
  encrypted from browsers to the gateway, and unencrypted from the gateway to
  OpenSearch Dashboards.

### Using your own certificate

Set `key_vault_secret_id` and `key_vault_identity_id` to serve OpenSearch Dashboards with
your own certificate. An Application Gateway then replaces the Load Balancer; it
is private unless `public = true`. Before the
first apply, ensure that:

1. For a private gateway, your subscription is registered for private Application Gateways:

   ```bash
   az feature register --namespace Microsoft.Network --name EnableApplicationGatewayNetworkIsolation
   az provider register --namespace Microsoft.Network
   ```

2. Key Vault holds the certificate for `dns_name`.
3. A user-assigned identity has **Key Vault Secrets User** on the vault. Set `key_vault_identity_id` to
   its ID, with `resourceGroups`.

With `certificates_integration`, also set `dashboards_load_balancer.ca_certificate`.

### Public OpenSearch Dashboards access

With `public = true`, the Application Gateway gets a public IP and accepts only `allowed_cidrs`:

```hcl
dashboards_load_balancer = {
  public                = true
  allowed_cidrs         = ["203.0.113.10/32"]
  dns_name              = "dashboards.example.com"
  key_vault_secret_id   = "https://my-vault.vault.azure.net/secrets/dashboards-certificate"
  key_vault_identity_id = "/subscriptions/<subscription>/resourceGroups/<group>/providers/Microsoft.ManagedIdentity/userAssignedIdentities/<identity>"
}
```

- `key_vault_secret_id` and `key_vault_identity_id`: required, as in
  [Using your own certificate](#using-your-own-certificate). The certificate should include `dns_name`.
- `dns_name`: create a public DNS record pointing it to `address` in the
  `dashboards_load_balancer` output.
  The address changes if you switch between public and private.

### Opening Grafana

On the COS Kubernetes cluster:

```bash
kubectl get svc -n cos traefik-lb -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
```

Open `http://<address>/cos-grafana` and log in as `admin`.

### Backups

With `backups` set, OpenSearch stores snapshots in the container under `path`
(`opensearch-vm-ld` by default):

```bash
juju run main/leader create-backup -m opensearch
juju run main/leader list-backups -m opensearch
juju run main/leader restore backup-id="<id>" -m opensearch
```

### Rotating the key

Export the new key and increment `azure_storage_secret_version`. The module
updates the Juju secret that `azure-storage-integrator` reads.

## Notes

- The OpenSearch Dashboards load balancer is private unless configured for public access.
- `self-signed-certificates` is intended for evaluation. Use your organization's
  certificate provider for production deployments (`certificates_integration`).
- COS Lite runs Grafana, Loki and Prometheus on 1G volumes by default. For
  anything beyond a demo, set the `cos` storage directives. See
  [customize storage options](https://documentation.ubuntu.com/observability/latest/how-to/configure-and-tune/customize-storage-options/).
