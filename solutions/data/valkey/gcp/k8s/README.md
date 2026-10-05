# Valkey on Kubernetes with TLS, COS Lite and GCS backups

Solution module that composes the [Valkey Kubernetes product module](https://github.com/canonical/valkey-operator/tree/dpe-10797-charm-product-tf-modules/terraform/product/k8s)
into a complete stack. You provide a bucket name, and the module handles the rest.

## Deployed stack

- Model `cos` (set `cos_model` to rename it): [COS Lite](https://github.com/canonical/observability-stack/tree/main/terraform/cos-lite), which
  offers Prometheus remote-write, Loki logging and Grafana dashboards.
- Model `valkey` (set `valkey_model` to rename it):
  - Valkey (3 units) and `data-integrator`, from the product module.
  - `opentelemetry-collector-k8s`, which forwards Valkey metrics, logs and dashboards to the COS
    Lite offers.
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
terraform apply -var gcs_bucket=my-valkey-backups
```

Set `k8s_cloud` when the controller's default cloud is not Kubernetes, for example on a controller
bootstrapped on LXD:

```bash
terraform apply -var gcs_bucket=my-valkey-backups -var k8s_cloud=microk8s
```

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
  -var gcs_service_account_email=valkey-backup@my-project.iam.gserviceaccount.com
```

`gcs_service_account_key` is ephemeral. Supply it at every plan and apply.

### Exposing Valkey outside the cluster

On GKE, set `load_balancer` to put the Valkey primary behind an external load balancer on a
static IP. Only the CIDRs you list can reach it:

```bash
terraform apply \
  -var gcs_bucket=my-valkey-backups \
  -var k8s_cloud=k8s \
  -var 'load_balancer={allowed_cidrs=["203.0.113.4/32"], gke_cluster="my-cluster", gke_location="us-central1"}'
terraform output valkey_external_endpoint
```

The module reserves a regional static IP, creates a `LoadBalancer` Service on the TLS port (6380)
that selects the pod the charm labels `role=primary`, and adds the IP to the server certificate
through `certificate-extra-sans`. Adding it to a running deployment makes the units request new
certificates.

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

Increment `gcs_key_version`. With a generated key, the module creates a new key, pushes it to
`gcs-integrator` and deletes the old one. With your own key, it pushes the key you supply at that
apply.

## Notes

- A new IAM binding can take a minute or two to take effect. Until it does, the charm can report
  bucket access errors, and it recovers on a later hook.
- The bucket is not created with `force_destroy`. `terraform destroy` fails while it still holds
  backups. Empty it first, or remove it from state (`terraform state rm google_storage_bucket.backups`)
  to keep it.
- COS Lite runs Grafana, Loki and Prometheus on 1G volumes by default, and plans warn about it. For
  anything beyond a demo, see
  [customize storage options](https://documentation.ubuntu.com/observability/latest/how-to/configure-and-tune/customize-storage-options/).
- The Valkey model and the COS model sit on the same controller, so the collector reaches COS
  through cross-model relations on the offers the COS Lite module creates.
