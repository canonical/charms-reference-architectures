# OpenSearch on Kubernetes on AWS with OpenSearch Dashboards, TLS, COS Lite and S3 backups

Solution module that composes the
[OpenSearch Kubernetes simple deployment product module](https://github.com/canonical/opensearch-operator/tree/efa6b48ea34b4cf5c03e19bbe5cfbaa662e8508f/terraform/kubernetes/product/simple_deployment)
into a complete stack on EKS. You provide the EKS cluster, and optionally an S3
bucket for backups, and the module handles the rest.

## Deployed stack

- Model `cos` (set `cos.model` to rename it):
  [COS Lite](https://github.com/canonical/observability-stack/tree/tf-cos-lite-3.0.3/terraform/cos-lite),
  which offers Prometheus remote-write, Loki logging and Grafana dashboards.
- Model `opensearch` (set `opensearch_model` to rename it):
  - OpenSearch (`opensearch-k8s`, 3 units), OpenSearch Dashboards
    (`opensearch-dashboards-k8s`, 3 units), `data-integrator` and
    `self-signed-certificates`, from the product module.
  - `traefik-k8s` in front of OpenSearch Dashboards, with an internal NLB.
  - `opentelemetry-collector-k8s`, which forwards metrics, logs and dashboards
    to the COS Lite offers.
  - With `backups` set, `s3-integrator` pointed at your bucket.

Set `cos = null` to deploy without COS Lite and the collector.

## Requirements

| Name      | Version |
| --------- | ------- |
| terraform | >= 1.12 |
| juju      | ~> 2.2  |

The controller needs the EKS cluster added as a Kubernetes cloud
(`juju add-k8s`). Both models are created on it.

OpenSearch needs `vm.swappiness = 0` on the EKS nodes. With this repository's
`clouds/aws` module, set `EKS_NODE_SYSCTLS={"vm.swappiness"="0"}` when you
create the cluster. Adding it later replaces all EKS nodes.

The module reads the Juju credentials from the environment: the Juju CLI's
current controller, or the `JUJU_*` variables.

The S3 keys are ephemeral inputs. Terraform does not store them in the plan or
the state. The product module hands them to `s3-integrator` through a Juju secret.

## Usage

```bash
terraform init
terraform apply
```

With backups, pass an existing bucket and its keys:

```bash
export TF_VAR_s3_access_key=<access key>
export TF_VAR_s3_secret_key=<secret key>
terraform apply -var 'backups={bucket="my-opensearch-backups", region="eu-central-1"}'
```

Set `k8s_cloud` to the name the EKS cluster has on the controller (`k8s` by
default). Both models use the controller credential named like `k8s_cloud`,
which is the name `juju add-k8s` gives it. If yours differs, set
`k8s_credential` (list them with `juju credentials --controller <controller>`).

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
juju run opensearch-k8s/leader get-password -m opensearch

# Grafana admin password.
juju run grafana/leader get-admin-password -m cos
```

### Connecting an application

`get-credentials` returns a user and an index for one application.
The endpoints are in-cluster names, for example
`opensearch-k8s-0.opensearch-k8s-endpoints.opensearch.svc.cluster.local:9200`,
so the application must run in the same cluster. From a pod, with the `tls-ca`
value saved in `ca.pem`:

```bash
curl --cacert ca.pem -u "<username>:<password>" "https://<endpoint>/<index>/_search?q=*"
```

Charms in the `opensearch` model can integrate with the `opensearch-k8s`
`opensearch-client` endpoint instead.

### Opening OpenSearch Dashboards

Traefik spreads requests over the OpenSearch Dashboards units. To get its NLB address:

```bash
kubectl get svc -n opensearch traefik-k8s-lb -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
```

Open `https://<address>/opensearch-opensearch-dashboards-k8s/` and log in as `admin`,
with the password from `juju run opensearch-k8s/leader get-password -m opensearch`.

- To use your own name, point it at the NLB in your DNS and set
  `dashboards_traefik = { config = { external_hostname = "<name>" } }`.
- `opensearch_dashboards.tls = false` turns off TLS between Traefik and
  OpenSearch Dashboards.

### Opening Grafana

```bash
kubectl get svc -n cos traefik-lb -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
```

Open `http://<address>/cos-grafana` and log in as `admin`.

### Backups

With `backups` set, OpenSearch stores snapshots in the bucket under `path`
(`opensearch-k8s` by default):

```bash
juju run opensearch-k8s/leader create-backup -m opensearch
juju run opensearch-k8s/leader list-backups -m opensearch
juju run opensearch-k8s/leader restore backup-id="<id>" -m opensearch
```

### Rotating the keys

Export the new keys and increment `s3_secret_version`. The module updates the
Juju secret that `s3-integrator` reads.

## Notes

- Both NLBs are internal. They are reachable only from inside the VPC by default.
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
| backups | Existing S3 bucket for backups. | <pre>object({<br/>    bucket = string<br/>    region = string<br/>    path   = optional(string, "opensearch-k8s")<br/>    config = optional(map(string), {})<br/>  })</pre> | `null` | no |
| certificates_integration | Optional offer of an external TLS provider for OpenSearch and OpenSearch Dashboards. | <pre>object({<br/>    url = string<br/>  })</pre> | `null` | no |
| cos | Model name, risk, storage sizes and Traefik config for COS Lite. | <pre>object({<br/>    model                         = optional(string, "cos")<br/>    grafana_storage_directives    = optional(map(string), { database = "1G" })<br/>    loki_storage_directives       = optional(map(string), { active-index-directory = "1G", loki-chunks = "1G" })<br/>    prometheus_storage_directives = optional(map(string), { database = "1G" })<br/>    risk                          = optional(string, "stable")<br/>    traefik_config                = optional(map(string), {})<br/>  })</pre> | `{}` | no |
| dashboards_load_balancer | OpenSearch Dashboards load balancer. Private by default; `public = true` exposes it to `allowed_cidrs`. | <pre>object({<br/>    public        = optional(bool, false)<br/>    allowed_cidrs = optional(set(string), [])<br/>    hostname      = optional(string)<br/>  })</pre> | `{}` | no |
| dashboards_traefik | Config for Traefik fronting OpenSearch Dashboards. | <pre>object({<br/>    config = optional(map(string), {})<br/>    certificates_integration = optional(object({<br/>      url = string<br/>    }))<br/>  })</pre> | `{}` | no |
| data_integrator | `data-integrator` configuration options. | <pre>object({<br/>    config   = optional(map(string), {})<br/>    channel  = optional(string, "latest/stable")<br/>    revision = optional(number)<br/>  })</pre> | `{}` | no |
| k8s_cloud | Kubernetes cloud for both models. | `string` | `"k8s"` | no |
| k8s_credential | Credential for `k8s_cloud`. | `string` | `null` | no |
| offered_endpoints | OpenSearch endpoints to offer to other models. | `list(string)` | `[]` | no |
| opensearch | OpenSearch app. | <pre>object({<br/>    config             = optional(map(string), {})<br/>    channel            = optional(string)<br/>    revision           = optional(number)<br/>    resources          = optional(map(string), {})<br/>    constraints        = optional(string)<br/>    units              = optional(number, 3)<br/>    storage_directives = optional(map(string), { opensearch-data = "20G" })<br/>  })</pre> | `{}` | no |
| opensearch_dashboards | OpenSearch Dashboards app. | <pre>object({<br/>    config    = optional(map(string), {})<br/>    channel   = optional(string)<br/>    revision  = optional(number)<br/>    resources = optional(map(string), {})<br/>    units     = optional(number, 3)<br/>    tls       = optional(bool, true)<br/>  })</pre> | `{}` | no |
| opensearch_model | Name of the model created for OpenSearch. | `string` | `"opensearch"` | no |
| risk | Risk of the OpenSearch and OpenSearch Dashboards channels (`2/<risk>`) when their `channel` isn't set. | `string` | `"edge"` | no |
| s3_access_key | S3 access key for `backups`. | `string` | `null` | no |
| s3_secret_key | S3 secret key for `backups`. | `string` | `null` | no |
| s3_secret_version | Version of the S3 keys. Increment to rotate them. | `number` | `1` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| app_names | Names of the applications deployed by the OpenSearch product module. |
| cos | COS Lite model UUID and offer URLs. null without COS. |
| metadata | Metadata of the OpenSearch product deployment. |
| models | Models by UUID, with the applications deployed in each. |
| offers | Map of all offers made by the OpenSearch product module. |
<!-- END_TF_DOCS -->
