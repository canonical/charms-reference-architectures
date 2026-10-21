# OpenSearch on GCP machines with OpenSearch Dashboards, TLS, COS Lite and GCS backups

Solution module that composes the
[OpenSearch machine simple deployment product module](https://github.com/canonical/opensearch-operator/tree/efa6b48ea34b4cf5c03e19bbe5cfbaa662e8508f/terraform/machine/product/simple_deployment)
into a complete stack on GCP virtual machines. You provide a Kubernetes cloud for COS Lite, and
optionally a GCS bucket for backups, and the module handles the rest.

## Deployed stack

- Model `cos` on `cos.cloud` (set `cos.model` to rename it):
  [COS Lite](https://github.com/canonical/observability-stack/tree/tf-cos-lite-3.0.3/terraform/cos-lite),
  which offers Prometheus remote-write, Loki logging and Grafana dashboards.
- Model `opensearch` on the controller's default cloud (set `opensearch_model`
  to rename it):
  - OpenSearch (3 units), OpenSearch Dashboards (3 units), `data-integrator` and
    `self-signed-certificates`, from the product module.
  - The `opentelemetry-collector` subordinate on each OpenSearch and OpenSearch Dashboards
    machine, which forwards metrics, logs and dashboards to the COS Lite offers.
  - With `backups` set, `gcs-integrator` pointed at your bucket.
- A Google Cloud load balancer, private by default, for the OpenSearch Dashboards
  machines (see [Public OpenSearch Dashboards access](#public-opensearch-dashboards-access)). With
  `dashboards_load_balancer.dns_name`, also a DNS name for it that resolves inside `network`.

Set `cos = null` to deploy without COS Lite and the collector. No Kubernetes
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

- Juju: the Juju CLI's current controller, or the `JUJU_*` variables.
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

Charm options go in `config`, for example:

```hcl
opensearch = {
  units  = 5
  config = { profile = "production" }
}
```

### Getting credentials

```bash
# Client credentials: endpoints, user, password, index and CA.
juju run data-integrator/leader get-credentials -m opensearch

# admin password
juju run opensearch/leader get-password -m opensearch

# OpenSearch Dashboards URL.
terraform output dashboards_load_balancer

# Grafana admin password.
juju run grafana/leader get-admin-password -m cos
```

### Connecting an application

`get-credentials` returns a user and an index for one application.
The endpoints are the private addresses of all OpenSearch units.
OpenSearch accepts connections from `opensearch.allowed_cidrs`.
With the `tls-ca` value saved in `ca.pem`:

```bash
curl --cacert ca.pem -u "<username>:<password>" "https://<endpoint>/<index>/_search?q=*"
```

Charms in the `opensearch` model can integrate with the `opensearch`
`opensearch-client` endpoint instead.

### Opening OpenSearch Dashboards

Open the `url` from `terraform output dashboards_load_balancer` and log in as
`admin`, with the password from `juju run opensearch/leader get-password -m opensearch`.

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
(`opensearch-vm` by default):

```bash
juju run opensearch/leader create-backup -m opensearch
juju run opensearch/leader list-backups -m opensearch
juju run opensearch/leader restore backup-id="<id>" -m opensearch
```

### Rotating the key

Export the new key and increment `gcs_secret_version`. The module
updates the Juju secret that `gcs-integrator` reads.

## Notes

- The OpenSearch Dashboards load balancer is private unless configured for public access.
- Changing `public` or `certificate_id` rebuilds the load balancer, which briefly
  interrupts OpenSearch Dashboards traffic.
- Choose `opensearch.constraints` before the first apply.
  Changing it later replaces the application.
- `self-signed-certificates` is intended for evaluation. Use your organization's
  certificate provider for production deployments (`certificates_integration`).
- COS Lite runs Grafana, Loki and Prometheus on 1G volumes by default. For
  anything beyond a demo, set the `cos` storage directives. See
  [customize storage options](https://documentation.ubuntu.com/observability/latest/how-to/configure-and-tune/customize-storage-options/).

<!-- BEGIN_TF_DOCS -->
## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| backups | Existing GCS bucket for backups. | <pre>object({<br/>    bucket = string<br/>    path   = optional(string, "opensearch-vm")<br/>    config = optional(map(string), {})<br/>  })</pre> | `null` | no |
| certificates_integration | Optional offer of an external TLS provider for OpenSearch and OpenSearch Dashboards. | <pre>object({<br/>    url = string<br/>  })</pre> | `null` | no |
| cos | Kubernetes cloud, credential, model name, risk, storage sizes and Traefik config for COS Lite. | <pre>object({<br/>    cloud                         = optional(string, "k8s")<br/>    credential                    = optional(string)<br/>    model                         = optional(string, "cos")<br/>    grafana_storage_directives    = optional(map(string), { database = "1G" })<br/>    loki_storage_directives       = optional(map(string), { active-index-directory = "1G", loki-chunks = "1G" })<br/>    prometheus_storage_directives = optional(map(string), { database = "1G" })<br/>    risk                          = optional(string, "stable")<br/>    traefik_config                = optional(map(string), {})<br/>  })</pre> | `{}` | no |
| dashboards_load_balancer | OpenSearch Dashboards load balancer. Private by default; `public = true` exposes it to `allowed_cidrs`. | <pre>object({<br/>    subnet              = optional(string, "deployments-clients-subnet")<br/>    backend_subnet      = optional(string, "deployments-subnet")<br/>    proxy_subnet_cidr   = optional(string, "10.5.0.0/23")<br/>    create_proxy_subnet = optional(bool, true)<br/>    certificate_id      = optional(string)<br/>    dns_name            = optional(string)<br/>    public              = optional(bool, false)<br/>    security_policy     = optional(string)<br/>    allowed_cidrs       = optional(set(string), [])<br/>  })</pre> | `{}` | no |
| data_integrator | `data-integrator` configuration options. | <pre>object({<br/>    config   = optional(map(string), {})<br/>    channel  = optional(string, "latest/stable")<br/>    revision = optional(number)<br/>  })</pre> | `{}` | no |
| excluded_subnets | CIDRs of subnets that machines must stay out of. | `list(string)` | `[]` | no |
| gcs_secret_key | GCS service-account key for `backups`. | `string` | `null` | no |
| gcs_secret_version | Version of the GCS key. Increment to rotate it. | `number` | `1` | no |
| integrator_constraints | Constraints for integrator apps. | `string` | `"cores=1 mem=2G"` | no |
| model_constraints | Constraints of the OpenSearch model. | `string` | `"allocate-public-ip=false"` | no |
| network | Existing GCP network for the OpenSearch model and the OpenSearch Dashboards load balancer. | `string` | `"main-vpc"` | no |
| offered_endpoints | OpenSearch endpoints to offer to other models. | `list(string)` | `[]` | no |
| opensearch | OpenSearch app. | <pre>object({<br/>    config             = optional(map(string), {})<br/>    channel            = optional(string)<br/>    revision           = optional(number)<br/>    constraints        = optional(string, "instance-type=e2-standard-2")<br/>    units              = optional(number, 3)<br/>    storage_directives = optional(map(string), { opensearch-data = "20G" })<br/>    allowed_cidrs      = optional(list(string), [])<br/>  })</pre> | `{}` | no |
| opensearch_dashboards | OpenSearch Dashboards app. | <pre>object({<br/>    config        = optional(map(string), {})<br/>    channel       = optional(string)<br/>    revision      = optional(number)<br/>    constraints   = optional(string, "instance-type=e2-medium")<br/>    units         = optional(number, 3)<br/>    tls           = optional(bool, true)<br/>    allowed_cidrs = optional(list(string), [])<br/>  })</pre> | `{}` | no |
| opensearch_model | Name of the model created for OpenSearch. | `string` | `"opensearch"` | no |
| risk | Risk of the OpenSearch and OpenSearch Dashboards channels (`2/<risk>`) when their `channel` isn't set. | `string` | `"edge"` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| app_names | Names of the applications deployed by the OpenSearch product module. |
| cos | COS Lite model UUID and offer URLs. null without COS. |
| dashboards_load_balancer | The load balancer's address and the URL to open OpenSearch Dashboards. |
| metadata | Metadata of the OpenSearch product deployment. |
| models | Models by UUID, with the applications deployed in each. |
| offers | Map of all offers made by the OpenSearch product module. |
<!-- END_TF_DOCS -->
