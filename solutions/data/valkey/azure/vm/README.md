# Valkey on Azure machines with TLS, COS Lite and Blob Storage backups

Solution module that composes the [Valkey machine product module](https://github.com/canonical/valkey-operator/tree/dpe-10797-charm-product-tf-modules/terraform/product/vm) into a
complete stack on Azure VMs. You provide a resource group, a storage account name and the name of
a Kubernetes cloud for COS Lite, and the module handles the rest.

## Deployed stack

- Model `cos` on `k8s_cloud` (set `cos_model` to rename it): [COS Lite](https://github.com/canonical/observability-stack/tree/main/terraform/cos-lite),
  which offers Prometheus remote-write, Loki logging and Grafana dashboards.
- Model `valkey` on the controller's default cloud or `machine_cloud` (set `valkey_model` to rename
  it). The module creates it and hands it to the product module:
  - Valkey (3 units, one machine each) and `data-integrator`, from the product module.
  - The `opentelemetry-collector` subordinate on each Valkey machine, which forwards Valkey
    metrics, logs and dashboards to the COS Lite offers.
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

The controller needs a machine cloud for Valkey and a Kubernetes cloud for COS Lite. For example,
bootstrap on Azure and add an AKS cluster with `juju add-k8s`.

The module reads credentials from the environment:

- Juju: the juju CLI's current controller, or the `JUJU_*` variables. Both models are created on
  that controller.
- Azure: the Azure CLI login (`az login`) or the `ARM_*` variables. `ARM_SUBSCRIPTION_ID` picks the
  subscription. The identity needs permission to create storage accounts in
  `azure_resource_group`. With `cos_ingress` set, it also needs to add a rule to its
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

The COS model uses the controller credential named like `k8s_cloud`, which is the name
`juju add-k8s` gives it. If yours differs, set `k8s_credential`. `juju credentials --controller
<controller>` lists them.

The Valkey model goes on the controller's default cloud. When that cloud is not the machine cloud
you want, set `machine_cloud`, and `machine_credential` if the cloud has more than one credential.

After apply:

```bash
# Client credentials. Clients must connect with TLS and trust the self-signed CA.
juju run data-integrator/leader get-credentials -m valkey
juju run self-signed-certificates/leader get-ca-certificate -m valkey

# Grafana admin password, for the dashboards Valkey ships.
juju run grafana/leader get-admin-password -m cos
```

### Keeping machines out of a subnet

By default Juju places machines in any subnet of the VNet, including the controller's. List the
subnets to avoid in `excluded_subnets`. The module moves them into a separate space in the Valkey
model and sets the model constraint `spaces=alpha`, so every machine lands in one of the remaining
subnets. With the [`clouds/azure`](../../../../../clouds/azure) module, exclude the controller
subnet:

```bash
terraform apply ... -var 'excluded_subnets=["10.1.0.0/16"]'
```

Set `excluded_subnets` before the first apply. Machines that already run in an excluded subnet stay
there.

### Reaching COS Lite from the machines

The collector pushes metrics and logs to Traefik's public load balancer on AKS. The machines reach
it from their outbound IP, such as a NAT gateway's, and an NSG on the AKS node subnet drops that
traffic unless a rule allows it. Set `cos_ingress` to add an inbound rule on ports 80 and 443 at
priority 4001. List the machines' outbound IPs so the collector can push, and your own IP to reach
Grafana:

```bash
terraform apply ... \
  -var 'cos_ingress={allowed_cidrs=["<nat ip>/32", "203.0.113.4/32"], network_security_group="main-nsg", resource_group="main-rg"}'
```

With the `clouds/azure` module, the NSG is `main-nsg` in `main-rg`, and the NAT gateway public IPs
are in the same resource group (`az network public-ip list -g main-rg`).

### Connecting from outside Azure

Juju on Azure gives every machine a public IP. Set `external_access` to reach Valkey on those IPs.
Juju exposes Valkey and adds rules for its TLS ports, 6380 and 26380, to the NSG that filters each
machine, open only to the CIDRs you list.

Azure assigns the public IPs when it creates the machines, so this takes two applies. Expose Valkey
first:

```bash
terraform apply \
  -var azure_resource_group=main-rg \
  -var azure_storage_account=myvalkeybackups \
  -var k8s_cloud=k8s \
  -var 'external_access={allowed_cidrs=["203.0.113.4/32"]}'
juju status valkey -m valkey   # the Public address column
```

Then add the public IPs to the server certificates through `certificate-extra-sans`. The units
request new certificates, and every certificate lists all the IPs:

```bash
terraform apply \
  -var azure_resource_group=main-rg \
  -var azure_storage_account=myvalkeybackups \
  -var k8s_cloud=k8s \
  -var 'external_access={allowed_cidrs=["203.0.113.4/32"], extra_sans=["<ip0>","<ip1>","<ip2>"]}'
```

Connect with the CA from `self-signed-certificates` and the credentials from `data-integrator`:

```bash
valkey-cli -h <primary public ip> -p 6380 --tls --cacert ca.pem --user <username> --pass <password>
```

- Clients connect in standalone mode, not Sentinel mode. On machines, Sentinel announces the
  units' private IPs, which an outside client cannot reach.
- Writes go to the primary only. Run `ROLE` to see which unit you reached. After a failover,
  reconnect to the new primary's public IP.
- If a machine's public IP changes, update `extra_sans` to match.
- `get-credentials` still reports the private endpoints.

### Rotating the key

Renew the primary key, then increment `azure_key_version`. The next apply reads the new key and
pushes it to `azure-storage-integrator`:

```bash
az storage account keys renew -g main-rg -n myvalkeybackups --key primary
terraform apply ... -var azure_key_version=2
```

## Notes

- `clouds/azure` defines the rules of `main-nsg` inline, so applying that module again deletes the
  `cos_ingress` rule. Apply this module again afterwards to restore it.
- `terraform destroy` deletes the storage account and every backup in it. To keep them, remove
  both from state first:
  `terraform state rm azurerm_storage_account.backups azurerm_storage_container.backups`.
- COS Lite runs Grafana, Loki and Prometheus on 1G volumes by default, and plans warn about it. For
  anything beyond a demo, see
  [customize storage options](https://documentation.ubuntu.com/observability/latest/how-to/configure-and-tune/customize-storage-options/).
- The Valkey model and the COS model sit on the same controller, so the collector reaches COS
  through cross-model relations on the offers the COS Lite module creates.
