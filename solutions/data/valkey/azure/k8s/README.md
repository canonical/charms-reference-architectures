# Valkey on Kubernetes on Azure with TLS, COS Lite and Blob Storage backups

Solution module that composes the [Valkey Kubernetes product module](https://github.com/canonical/valkey-operator/tree/9/edge/terraform/product/k8s)
into a complete stack on AKS. You provide a resource group and a storage account name, and the
module handles the rest.

## Deployed stack

- Model `cos` (set `cos_model` to rename it): [COS Lite](https://github.com/canonical/observability-stack/tree/main/terraform/cos-lite), which
  offers Prometheus remote-write, Loki logging and Grafana dashboards.
- Model `valkey` (set `valkey_model` to rename it):
  - Valkey (3 units) and `data-integrator`, from the product module.
  - `opentelemetry-collector-k8s`, which forwards Valkey metrics, logs and dashboards to the COS
    Lite offers.
  - `self-signed-certificates` on the Valkey `client-certificates` endpoint, which turns on client
    TLS.
  - `azure-storage-integrator` on the Valkey `azure-credentials` endpoint, pointed at the container
    below.
- In Azure:
  - A Standard LRS storage account in `azure_resource_group`, with public access to blobs turned
    off.
  - A blob container in that account.

## Requirements

| Name      | Version  |
| --------- | -------- |
| terraform | >= 1.11  |
| juju      | >= 2.2.1 |
| azurerm   | >= 4.0   |

The module reads credentials from the environment:

- Juju: the juju CLI's current controller, or the `JUJU_*` variables. Both models are created on
  that controller, which needs the AKS cluster added as a Kubernetes cloud (`juju add-k8s`).
- Azure: the Azure CLI login (`az login`) or the `ARM_*` variables. `ARM_SUBSCRIPTION_ID` picks the
  subscription. The identity needs permission to create storage accounts in
  `azure_resource_group`. With `load_balancer` set, it also needs to read the AKS cluster
  credentials, create a public IP in the cluster's node resource group, and add a rule to
  `network_security_group`.

Terraform stores the storage account key in state. Keep the state in an encrypted remote backend
with restricted access. The key never appears in Juju relation data or in the plan output.

## Usage

```bash
export ARM_SUBSCRIPTION_ID=00000000-0000-0000-0000-000000000000
terraform init
terraform apply \
  -var azure_resource_group=main-rg \
  -var azure_storage_account=myvalkeybackups \
  -var k8s_cloud=k8s
```

Set `k8s_cloud` to the name the AKS cluster has on the controller. A controller bootstrapped on
Azure defaults to the `azure` cloud, which cannot host these models.

Both models use the controller credential named like `k8s_cloud`, which is the name `juju add-k8s`
gives it. If yours differs, set `k8s_credential` (list them with `juju credentials --controller
<controller>`).

After apply:

```bash
# Client credentials. Clients must connect with TLS and trust the self-signed CA.
juju run data-integrator/leader get-credentials -m valkey
juju run self-signed-certificates/leader get-ca-certificate -m valkey

# Grafana admin password, for the dashboards Valkey ships.
juju run grafana/leader get-admin-password -m cos
```

### Exposing Valkey outside the cluster

Set `load_balancer` to put the Valkey primary behind the AKS public load balancer on a static IP.
Only the CIDRs you list can reach it:

```bash
terraform apply \
  -var azure_resource_group=main-rg \
  -var azure_storage_account=myvalkeybackups \
  -var k8s_cloud=k8s \
  -var 'load_balancer={allowed_cidrs=["203.0.113.4/32"], aks_cluster="aks-cluster", resource_group="main-rg", network_security_group="main-nsg"}'
terraform output valkey_external_endpoint
```

`aks_cluster` and `resource_group` name the cluster behind `k8s_cloud`. The module creates the
Service with the client certificate from the cluster's kubeconfig, so the cluster must allow local
accounts.

The module reserves a static public IP in the cluster's node resource group and creates a
`LoadBalancer` Service on the TLS port (6380) that selects the pod the charm labels `role=primary`.
It adds the IP to the server certificate through `certificate-extra-sans`. Adding it to a running
deployment makes the units request new certificates.

AKS opens the port in the NSG it manages on the nodes' network interfaces. An NSG on the node
subnet filters the same traffic, so name it in `network_security_group` and the module adds an
inbound rule for `allowed_cidrs` on port 6380 at priority 4000. With the
[`clouds/azure`](../../../../../clouds/azure) module, that NSG is `main-nsg`. Leave it unset when the
node subnet has no NSG.

Connect with the CA from `self-signed-certificates` and the credentials from `data-integrator`:

```bash
valkey-cli -h <ip> -p 6380 --tls --cacert ca.pem --user <username> --pass <password>
```

- Clients connect in standalone mode, not Sentinel mode. Sentinel announces in-cluster hostnames
  that an outside client cannot resolve.
- On failover, open connections drop. The charm moves the `role=primary` label to the new primary,
  and clients that reconnect to the same IP reach it.
- Only the primary is exposed, so reads and writes both go to it.
- `get-credentials` still reports the in-cluster endpoints. Use the Terraform output for the
  address.

### Rotating the key

Renew the primary key, then increment `azure_key_version`. The next apply reads the new key and
pushes it to `azure-storage-integrator`:

```bash
az storage account keys renew -g main-rg -n myvalkeybackups --key primary
terraform apply ... -var azure_key_version=2
```

## Notes

- `clouds/azure` defines the rules of `main-nsg` inline, so applying that module again deletes the
  rule this module adds. Apply this module again afterwards to restore it.
- `terraform destroy` deletes the storage account and every backup in it. To keep them, remove
  both from state first:
  `terraform state rm azurerm_storage_account.backups azurerm_storage_container.backups`.
- COS Lite runs Grafana, Loki and Prometheus on 1G volumes by default, and plans warn about it. For
  anything beyond a demo, see
  [customize storage options](https://documentation.ubuntu.com/observability/latest/how-to/configure-and-tune/customize-storage-options/).
