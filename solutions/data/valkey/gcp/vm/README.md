# Valkey on machines with TLS, COS Lite and GCS backups

Solution module that composes the [Valkey machine product module](https://github.com/canonical/valkey-operator/tree/dpe-10797-charm-product-tf-modules/terraform/product/vm) into a
complete stack. You provide a bucket name and the name of a Kubernetes cloud for COS Lite, and the
module handles the rest.

## Deployed stack

- Model `cos` on `k8s_cloud` (set `cos_model` to rename it): [COS Lite](https://github.com/canonical/observability-stack/tree/main/terraform/cos-lite),
  which offers Prometheus remote-write, Loki logging and Grafana dashboards.
- Model `valkey` on the controller's default cloud or `machine_cloud` (set `valkey_model` to rename it):
  - Valkey (3 units, one machine each) and `data-integrator`, from the product module.
  - The `opentelemetry-collector` subordinate on each Valkey machine, which forwards Valkey
    metrics, logs and dashboards to the COS Lite offers.
  - `self-signed-certificates` on the Valkey `client-certificates` endpoint, which turns on client
    TLS.
  - `gcs-integrator` on the Valkey `gcs-credentials` endpoint, pointed at the bucket below.
- In GCP:
  - A bucket with uniform bucket-level access and public access prevention enforced.
  - A service account with `roles/storage.objectAdmin` on that bucket only, and a JSON key for
    it. The module skips both when you bring your own service account.

## Requirements

| Name      | Version  |
| --------- | -------- |
| terraform | >= 1.11  |
| juju      | >= 2.2.1 |
| google    | >= 6.0   |

The controller needs a machine cloud for Valkey and a Kubernetes cloud for COS Lite. For example,
bootstrap on GCE and add a GKE cluster with `juju add-k8s`.

The module reads credentials from the environment:

- Juju: the juju CLI's current controller, or the `JUJU_*` variables. Both models are created on
  that controller.
- GCP: Application Default Credentials (`gcloud auth application-default login`) or
  `GOOGLE_CREDENTIALS`. Set the project with `gcp_project` or `GOOGLE_PROJECT`. The identity needs
  permission to create buckets, service accounts and service-account keys, and to set bucket IAM.

## Usage

```bash
export GOOGLE_PROJECT=my-project
terraform init
terraform apply -var gcs_bucket=my-valkey-backups -var k8s_cloud=gke
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

### Bringing your own service account

By default the module creates a service account and a key. Terraform stores the generated key's
private part in state, because the google provider returns it only as a resource attribute. Keep
the state in an encrypted remote backend with restricted access. The key never appears in Juju
relation data or in the plan output.

To keep the key out of state, supply your own service account. The module still creates the bucket
and grants the account access to it:

```bash
export TF_VAR_gcs_service_account_key="$(cat key.json)"
terraform apply \
  -var gcs_bucket=my-valkey-backups \
  -var k8s_cloud=gke \
  -var gcs_service_account_email=valkey-backup@my-project.iam.gserviceaccount.com
```

`gcs_service_account_key` is ephemeral. Supply it at every plan and apply.

### Connecting from outside GCP

Set `external_access` to reach Valkey on the units' public IPs. Juju exposes Valkey and opens a GCE
firewall rule for its TLS ports, 6380 and 26380, that only the CIDRs you list can reach.

GCE assigns the public IPs when it creates the machines, so this takes two applies. Expose Valkey
first:

```bash
terraform apply \
  -var gcs_bucket=my-valkey-backups \
  -var k8s_cloud=gke \
  -var 'external_access={allowed_cidrs=["203.0.113.4/32"]}'
juju status valkey -m valkey   # the Public address column
```

Then add the public IPs to the server certificates through `certificate-extra-sans`. The units
request new certificates, and every certificate lists all the IPs:

```bash
terraform apply \
  -var gcs_bucket=my-valkey-backups \
  -var k8s_cloud=gke \
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
- The public IPs are ephemeral. If a machine is stopped and started, GCE gives it a new one, so
  update `extra_sans` to match.
- `get-credentials` still reports the private endpoints.

### Rotating the key

Increment `gcs_key_version`. With a generated key, the module creates a new key, pushes it to
`gcs-integrator` and deletes the old one. With your own key, it pushes the key you supply at that
apply.

## Notes

- The collector pushes metrics and logs to the addresses COS Lite advertises through Traefik, so
  the Valkey machines must reach Traefik's address. On GKE, Traefik's `LoadBalancer` Service gets
  an address that GCE machines in the same project can reach.
- A new IAM binding can take a minute or two to take effect. Until it does, the charm can report
  bucket access errors, and it recovers on a later hook.
- The bucket is not created with `force_destroy`. `terraform destroy` fails while it still holds
  backups. Empty it first, or remove it from state with
  `terraform state rm google_storage_bucket.backups` to keep it.
- COS Lite runs Grafana, Loki and Prometheus on 1G volumes by default, and plans warn about it. For
  anything beyond a demo, see
  [customize storage options](https://documentation.ubuntu.com/observability/latest/how-to/configure-and-tune/customize-storage-options/).
- The Valkey model and the COS model sit on the same controller, so the collector reaches COS
  through cross-model relations on the offers the COS Lite module creates.
