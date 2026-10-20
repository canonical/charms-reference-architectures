# OpenSearch large deployment on GCP machines with OpenSearch Dashboards, TLS, COS Lite and GCS backups

Solution module that composes the
[OpenSearch machine large deployment product module](https://github.com/canonical/opensearch-operator/tree/2/edge/terraform/machine/product/large_deployment)
into a complete stack on GCP virtual machines. You provide a Kubernetes cloud for COS Lite, and
optionally a GCS bucket for backups, and the module handles the rest.

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
  - With `backups` set, `gcs-integrator` pointed at your bucket.
- Each model in `extra_models`: the OpenSearch apps you place
  there, and its own `opentelemetry-collector`.
- A Google Cloud load balancer, private by default, for the OpenSearch Dashboards
  machines (see [Public OpenSearch Dashboards access](#public-opensearch-dashboards-access)). With
  `dashboards_load_balancer.dns_name`, also a DNS name for it that resolves inside `network`.

Set `cos = null` to deploy without COS Lite and the collectors. No Kubernetes
cloud is then needed. Set `dashboards_load_balancer = null` to skip the load
balancer.

## Requirements

| Name      | Version  |
| --------- | -------- |
| terraform | >= 1.12  |
| juju      | ~> 2.3   |
| google    | >= 8.7.0 |
| external  | >= 2.0   |

The controller needs the GCP machine cloud as its default cloud, and a
Kubernetes cloud for COS Lite (`juju add-k8s`).

The module reads credentials from the environment:

- Juju: the Juju CLI's current controller, or the `JUJU_*` variables. Terraform also
  runs `juju` and `jq` to wait for `failover`, so the CLI must use the same controller.
- GCP: Application Default Credentials (`gcloud auth application-default login`) or
  `GOOGLE_CREDENTIALS`, plus `GOOGLE_PROJECT` and `GOOGLE_REGION`. The identity needs
  permission to manage load balancers, network endpoint groups, firewall rules and
  subnets, and Cloud DNS with `dns_name`.

The network defaults match this repository's `clouds/gcp` module. For another network,
set `network` and the `dashboards_load_balancer` subnets. If the region already has a
proxy-only subnet, set `dashboards_load_balancer.create_proxy_subnet = false` and its
range in `dashboards_load_balancer.proxy_subnet_cidr`.

The GCS key is an ephemeral input. Terraform does not store it in the plan or the state.
The product module hands it to `gcs-integrator` through a Juju secret.

## Usage

```bash
export GOOGLE_PROJECT=<project id> GOOGLE_REGION=<region>
terraform init
terraform apply
```

With backups, pass an existing bucket and the key of a service account with
`roles/storage.objectAdmin` and `roles/storage.legacyBucketReader` on it. Pass the key
base64url-encoded on one line:

```bash
export TF_VAR_gcs_secret_key="$(base64 -w0 backup-sa-key.json | tr '+/' '-_')"
terraform apply -var 'backups={bucket="my-opensearch-backups"}'
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
    constraints = "instance-type=n2-standard-8"
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
Each app accepts connections from its `allowed_cidrs`.
With the `tls-ca` value saved in `ca.pem`:

```bash
curl --cacert ca.pem -u "<username>:<password>" "https://<endpoint>/<index>/_search?q=*"
```

Charms in the `opensearch` model can integrate with the `main`
`opensearch-client` endpoint instead.

### Opening OpenSearch Dashboards

Open the `url` from `terraform output dashboards_load_balancer` and log in as
`admin`, with the password from `juju run main/leader get-password -m opensearch`.

By default, a private TCP proxy load balancer passes TLS through to the
OpenSearch Dashboards units. To end TLS at the load balancer with your own certificate:

```hcl
dashboards_load_balancer = {
  certificate_id = "projects/<project>/locations/<region>/certificates/dashboards"
  dns_name       = "dashboards.example.internal"
}
```

- `certificate_id`: a Certificate Manager certificate in the load balancer's region.
  A private Application Load Balancer then replaces the TCP proxy. The certificate
  should include `dns_name`.
- `dns_name`: optional. A private DNS zone in `network` points this name to the
  load balancer.
- `opensearch_dashboards.tls = false`: turns off TLS on OpenSearch Dashboards.
  Without `certificate_id`, traffic is then unencrypted. With it, traffic is
  encrypted only up to the load balancer.

### Public OpenSearch Dashboards access

With `public = true`, the load balancer is internet-facing and accepts only `allowed_cidrs`:

```hcl
dashboards_load_balancer = {
  public         = true
  certificate_id = "projects/<project>/locations/<region>/certificates/dashboards"
  allowed_cidrs  = ["203.0.113.5/32"]
  dns_name       = "dashboards.example.com"
}
```

- `certificate_id`: required. A Certificate Manager certificate in the load balancer's
  region. It should include `dns_name`.
- `security_policy`: your own regional Cloud Armor policy, instead of `allowed_cidrs`.
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

With `backups` set, OpenSearch stores snapshots in the bucket under `path`
(`opensearch-vm-ld` by default):

```bash
juju run main/leader create-backup -m opensearch
juju run main/leader list-backups -m opensearch
juju run main/leader restore backup-id="<id>" -m opensearch
```

### Rotating the key

Export the new key and increment `gcs_secret_version`. The module
updates the Juju secret that `gcs-integrator` reads.

## Notes

- The OpenSearch Dashboards load balancer is private unless configured for public access.
- Changing `public` or `certificate_id` rebuilds the load balancer, which briefly
  interrupts OpenSearch Dashboards traffic.
- `self-signed-certificates` is intended for evaluation. Use your organization's
  certificate provider for production deployments (`certificates_integration`).
- COS Lite runs Grafana, Loki and Prometheus on 1G volumes by default. For
  anything beyond a demo, set the `cos` storage directives. See
  [customize storage options](https://documentation.ubuntu.com/observability/latest/how-to/configure-and-tune/customize-storage-options/).
