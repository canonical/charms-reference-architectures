# OpenSearch large deployment on Kubernetes on GCP with OpenSearch Dashboards, TLS, COS Lite and GCS backups

Solution module that composes the
[OpenSearch Kubernetes large deployment product module](https://github.com/canonical/opensearch-operator/tree/efa6b48ea34b4cf5c03e19bbe5cfbaa662e8508f/terraform/kubernetes/product/large_deployment)
into a complete stack on GKE. You provide the GKE cluster, and optionally a GCS
bucket for backups, and the module handles the rest.

A large deployment is one OpenSearch cluster made of several OpenSearch
applications, where each application can have its own roles:

- `main`: the main orchestrator.
- `failover`: the failover orchestrator.
- `apps`: the other applications, for example data nodes.

## Deployed stack

- Model `cos` (set `cos.model` to rename it):
  [COS Lite](https://github.com/canonical/observability-stack/tree/tf-cos-lite-3.0.3/terraform/cos-lite),
  which offers Prometheus remote-write, Loki logging and Grafana dashboards.
- Model `opensearch` (set `opensearch_model` to rename it):
  - OpenSearch `main` and `failover` (with `cluster_manager` role) and one app in
    `apps`, `data` (with `data` role), 3 units each. The product module also
    deploys OpenSearch Dashboards (`opensearch-dashboards-k8s`, 3 units),
    `data-integrator` and `self-signed-certificates`.
  - `traefik-k8s` in front of OpenSearch Dashboards, with a private GKE load balancer
    (see [Public OpenSearch Dashboards access](#public-opensearch-dashboards-access)).
  - `opentelemetry-collector-k8s`, which forwards metrics, logs and dashboards
    to the COS Lite offers.
  - With `backups` set, `gcs-integrator` pointed at your bucket.
- Each model in `extra_models`: the OpenSearch apps you place
  there, and its own `opentelemetry-collector-k8s`.

Set `cos = null` to deploy without COS Lite and the collectors.

## Requirements

| Name      | Version  |
| --------- | -------- |
| terraform | >= 1.12  |
| juju      | ~> 2.3   |
| google    | >= 8.7.0 |

The controller needs the GKE cluster added as a Kubernetes cloud
(`juju add-k8s`). All models are created on it.

OpenSearch needs `vm.swappiness = 0` and `vm.max_map_count` of at least 262144
on the GKE nodes. With this repository's `clouds/gcp` module, set
`GKE_NODE_SYSCTLS={"vm.swappiness"="0","vm.max_map_count"="262144"}` when you
create the cluster. This module doesn't set them.

The module reads credentials from the environment:

- Juju: the Juju CLI's current controller, or the `JUJU_*` variables.
- GCP: Application Default Credentials (`gcloud auth application-default login`)
  or an attached service account, plus `GOOGLE_PROJECT` and `GOOGLE_REGION`. The
  Google provider is used in private mode too, so it always needs credentials.

When an app in `apps` has the `cluster_manager` role, the product module waits for
`failover` with a script that runs `juju` and `jq` on the machine running Terraform,
against the Juju CLI's current controller.

The GCS service-account key is an ephemeral input. Terraform does not store it in
the plan or the state. The product module hands it to `gcs-integrator` through a
Juju secret.

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
export TF_VAR_gcs_secret_key="$(base64 -w0 <service account key>.json | tr '+/' '-_')"
terraform apply -var 'backups={bucket="my-opensearch-backups"}'
```

Set `k8s_cloud` to the name the GKE cluster has on the controller (`k8s` by
default). All models use the controller credential named like `k8s_cloud`,
which is the name `juju add-k8s` gives it. If yours differs, set
`k8s_credential` (list them with `juju credentials --controller <controller>`).

### Getting credentials

```bash
# Client credentials: endpoints, user, password, index and CA.
juju run data-integrator/leader get-credentials -m opensearch

# admin password
juju run main/leader get-password -m opensearch

# Grafana admin password.
juju run grafana/leader get-admin-password -m cos
```

### Choosing the OpenSearch apps

Set `apps` to the applications you need:

```hcl
apps = [
  { app_name = "data-hot", config = { roles = "data.hot" } },
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
The endpoints are in-cluster names of all OpenSearch units, for example
`main-0.main-endpoints.opensearch.svc.cluster.local:9200`, so the application
must run in the same cluster. From a pod, with the `tls-ca` value saved in
`ca.pem`:

```bash
curl --cacert ca.pem -u "<username>:<password>" "https://<endpoint>/<index>/_search?q=*"
```

Charms in the `opensearch` model can integrate with the `main`
`opensearch-client` endpoint instead.

### Opening OpenSearch Dashboards

Traefik spreads requests over the OpenSearch Dashboards units. To get its load balancer address:

```bash
kubectl get svc -n opensearch traefik-k8s-lb -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
```

Open `https://<address>/opensearch-opensearch-dashboards-k8s/` and log in as `admin`,
with the password from `juju run main/leader get-password -m opensearch`.

- `dashboards_load_balancer.hostname`: your own name for OpenSearch Dashboards. Point it at the
  load balancer's address in your DNS.
- `opensearch_dashboards.tls = false` turns off TLS between Traefik and
  OpenSearch Dashboards.

### Public OpenSearch Dashboards access

With `public = true`, the load balancer is internet-facing and accepts only `allowed_cidrs`:

```hcl
dashboards_load_balancer = {
  public        = true
  allowed_cidrs = ["203.0.113.5/32"]
  hostname      = "dashboards.example.com"
}
```

- `hostname`: optional. Create a public DNS record pointing it to `address` in the
  `dashboards_public_endpoint` output. The address changes if you switch between public and private.
- `network`: the GKE cluster's VPC (`main-vpc` by default).

Traefik keeps the certificate from `self-signed-certificates` unless you set
`dashboards_traefik.certificates_integration`.

### Opening Grafana

```bash
kubectl get svc -n cos traefik-lb -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
```

Open `http://<address>/cos-grafana` and log in as `admin`.

### Backups

With `backups` set, OpenSearch stores snapshots in the bucket under `path`
(`opensearch-k8s-ld` by default):

```bash
juju run main/leader create-backup -m opensearch
juju run main/leader list-backups -m opensearch
juju run main/leader restore backup-id="<id>" -m opensearch
```

### Rotating the key

Export the new key and increment `gcs_secret_version`. The module updates the
Juju secret that `gcs-integrator` reads.

## Notes

- The OpenSearch Dashboards load balancer is private unless configured for public access.
- Charm revisions are not pinned unless you set `revision`.
- Kubernetes may place several pods of one OpenSearch app on the same node. To keep them on
  different nodes, add a pod anti-affinity rule to the app's constraints, for example
  `main = { constraints = "tags=anti-pod.app.kubernetes.io/name=main,anti-pod.topology-key=kubernetes.io/hostname" }`,
  and the same for `failover` and each app in `apps` with its own name.
  The cluster then needs at least as many nodes as the units of each app.
- `self-signed-certificates` is intended for evaluation. Use your organization's
  certificate provider for production deployments (`certificates_integration`).
- COS Lite runs Grafana, Loki and Prometheus on 1G volumes by default. For
  anything beyond a demo, set the `cos` storage directives. See
  [customize storage options](https://documentation.ubuntu.com/observability/latest/how-to/configure-and-tune/customize-storage-options/).

<!-- BEGIN_TF_DOCS -->
## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| apps | Non-orchestrator OpenSearch apps. | <pre>list(object({<br/>    app_name           = string<br/>    config             = optional(map(string), {})<br/>    constraints        = optional(string)<br/>    units              = optional(number, 3)<br/>    storage_directives = optional(map(string), { opensearch-data = "20G" })<br/>    model              = optional(string)<br/>  }))</pre> | <pre>[<br/>  {<br/>    "app_name": "data",<br/>    "config": {<br/>      "roles": "data"<br/>    },<br/>    "model": "opensearch-data"<br/>  }<br/>]</pre> | no |
| backups | Existing GCS bucket for backups. | <pre>object({<br/>    bucket = string<br/>    path   = optional(string, "opensearch-k8s-ld")<br/>    config = optional(map(string), {})<br/>  })</pre> | `null` | no |
| certificates_integration | Optional offer of an external TLS provider for OpenSearch and OpenSearch Dashboards. | <pre>object({<br/>    url = string<br/>  })</pre> | `null` | no |
| cos | Model name, risk, storage sizes and Traefik config for COS Lite. | <pre>object({<br/>    model                         = optional(string, "cos")<br/>    grafana_storage_directives    = optional(map(string), { database = "1G" })<br/>    loki_storage_directives       = optional(map(string), { active-index-directory = "1G", loki-chunks = "1G" })<br/>    prometheus_storage_directives = optional(map(string), { database = "1G" })<br/>    risk                          = optional(string, "stable")<br/>    traefik_config                = optional(map(string), {})<br/>  })</pre> | `{}` | no |
| dashboards_load_balancer | OpenSearch Dashboards load balancer. Private by default; `public = true` exposes it to `allowed_cidrs`. | <pre>object({<br/>    public         = optional(bool, false)<br/>    allowed_cidrs  = optional(set(string), [])<br/>    hostname       = optional(string)<br/>    name           = optional(string, "opensearch-dashboards")<br/>    allow_priority = optional(number, 800)<br/>    deny_priority  = optional(number, 900)<br/>  })</pre> | `{}` | no |
| dashboards_traefik | Config for Traefik fronting OpenSearch Dashboards. | <pre>object({<br/>    config = optional(map(string), {})<br/>    certificates_integration = optional(object({<br/>      url = string<br/>    }))<br/>  })</pre> | `{}` | no |
| data_integrator | `data-integrator` configuration options. | <pre>object({<br/>    config   = optional(map(string), {})<br/>    channel  = optional(string, "latest/stable")<br/>    revision = optional(number)<br/>  })</pre> | `{}` | no |
| extra_models | Names of extra models for OpenSearch apps. | `list(string)` | <pre>[<br/>  "opensearch-failover",<br/>  "opensearch-data"<br/>]</pre> | no |
| failover | Failover orchestrator app. | <pre>object({<br/>    config             = optional(map(string), {})<br/>    constraints        = optional(string)<br/>    units              = optional(number, 3)<br/>    storage_directives = optional(map(string), { opensearch-data = "20G" })<br/>    model              = optional(string)<br/>  })</pre> | <pre>{<br/>  "model": "opensearch-failover"<br/>}</pre> | no |
| gcs_secret_key | GCS service-account key for `backups`. | `string` | `null` | no |
| gcs_secret_version | Version of the GCS key. Increment to rotate it. | `number` | `1` | no |
| k8s_cloud | Kubernetes cloud for all models. | `string` | `"k8s"` | no |
| k8s_credential | Credential for `k8s_cloud`. | `string` | `null` | no |
| main | Main orchestrator app. | <pre>object({<br/>    config             = optional(map(string), {})<br/>    constraints        = optional(string)<br/>    units              = optional(number, 3)<br/>    storage_directives = optional(map(string), { opensearch-data = "20G" })<br/>  })</pre> | `{}` | no |
| network | GCP network of the GKE cluster. | `string` | `"main-vpc"` | no |
| offered_endpoints | OpenSearch endpoints to offer to other models. | `list(string)` | `[]` | no |
| opensearch_charm | OpenSearch charm for all OpenSearch apps. | <pre>object({<br/>    channel   = optional(string)<br/>    profile   = optional(string, "testing")<br/>    revision  = optional(number)<br/>    resources = optional(map(string), {})<br/>  })</pre> | `{}` | no |
| opensearch_dashboards | OpenSearch Dashboards app. | <pre>object({<br/>    config    = optional(map(string), {})<br/>    channel   = optional(string)<br/>    revision  = optional(number)<br/>    resources = optional(map(string), {})<br/>    units     = optional(number, 3)<br/>    tls       = optional(bool, true)<br/>  })</pre> | `{}` | no |
| opensearch_model | Name of the model created for OpenSearch. | `string` | `"opensearch"` | no |
| risk | Risk of the OpenSearch and OpenSearch Dashboards channels (`2/<risk>`) when their `channel` isn't set. | `string` | `"edge"` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| app_names | Names of the applications deployed by the OpenSearch product module. |
| cos | COS Lite model UUID and offer URLs. null without COS. |
| dashboards_public_endpoint | The public load balancer's address and the URL to open OpenSearch Dashboards, or null when private. |
| metadata | Metadata of the OpenSearch product deployment. |
| models | Models by UUID, with the applications deployed in each. |
| offers | Map of all offers made by the OpenSearch product module. |
<!-- END_TF_DOCS -->
