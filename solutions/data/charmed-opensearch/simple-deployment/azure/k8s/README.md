# OpenSearch on Kubernetes on Azure with OpenSearch Dashboards, TLS, COS Lite and Azure Storage backups

Solution module that composes the
[OpenSearch Kubernetes simple deployment product module](https://github.com/canonical/opensearch-operator/tree/2/edge/terraform/kubernetes/product/simple_deployment)
into a complete stack on AKS. You provide the AKS cluster, and optionally an Azure storage
container for backups, and the module handles the rest.

## Deployed stack

- Model `cos` (set `cos.model` to rename it):
  [COS Lite](https://github.com/canonical/observability-stack/tree/tf-cos-lite-3.0.3/terraform/cos-lite),
  which offers Prometheus remote-write, Loki logging and Grafana dashboards.
- Model `opensearch` (set `opensearch_model` to rename it):
  - OpenSearch (`opensearch-k8s`, 3 units), OpenSearch Dashboards
    (`opensearch-dashboards-k8s`, 3 units), `data-integrator` and
    `self-signed-certificates`, from the product module.
  - `traefik-k8s` in front of OpenSearch Dashboards, with an internal Azure load balancer.
  - `opentelemetry-collector-k8s`, which forwards metrics, logs and dashboards
    to the COS Lite offers.
  - With `backups` set, `azure-storage-integrator` pointed at your container.
- A DaemonSet, `os-node-settings-<opensearch_model>` in `kube-system`, which sets
  the kernel settings OpenSearch needs on every AKS node.

Set `cos = null` to deploy without COS Lite and the collector.

## Requirements

| Name       | Version |
| ---------- | ------- |
| terraform  | >= 1.12 |
| juju       | ~> 2.2  |
| kubernetes | ~> 3.0  |

The controller needs the AKS cluster added as a Kubernetes cloud
(`juju add-k8s`). Both models are created on it.

OpenSearch needs `vm.swappiness = 0` and `vm.max_map_count` of at least 262144
on the AKS nodes. The DaemonSet sets both on every node, so the module also
needs access to the cluster.

With this repository's `clouds/azure` module, set
`AKS_SUBNET_NETWORK_CONTRIBUTOR=true`, so that AKS can create the internal load
balancers.

The module reads credentials from the environment:

- Juju: the Juju CLI's current controller, or the `JUJU_*` variables.
- Kubernetes: `KUBE_CONFIG_PATH`, the AKS cluster's kubeconfig.

The storage account key is an ephemeral input. Terraform does not store it in
the plan or the state. The product module hands it to `azure-storage-integrator`
through a Juju secret.

## Usage

```bash
export KUBE_CONFIG_PATH=<AKS kubeconfig>
terraform init
terraform apply
```

With backups, pass an existing storage account and container, and the account's key:

```bash
export TF_VAR_azure_storage_secret_key=<storage account key>
terraform apply -var 'backups={storage_account="myopensearchbackups", container="opensearch-backups"}'
```

Set `k8s_cloud` to the name the AKS cluster has on the controller (`k8s` by
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

Traefik spreads requests over the OpenSearch Dashboards units. To get its load balancer address:

```bash
kubectl get svc -n opensearch traefik-k8s-lb -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
```

Open `https://<address>/opensearch-opensearch-dashboards-k8s/` and log in as `admin`,
with the password from `juju run opensearch-k8s/leader get-password -m opensearch`.

- To use your own name, point it at the load balancer in your DNS and set
  `dashboards_traefik = { config = { external_hostname = "<name>" } }`.
- `opensearch_dashboards.tls = false` turns off TLS between Traefik and
  OpenSearch Dashboards.

### Opening Grafana

```bash
kubectl get svc -n cos traefik-lb -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
```

Open `http://<address>/cos-grafana` and log in as `admin`.

### Backups

With `backups` set, OpenSearch stores snapshots in the container under `path`
(`opensearch-k8s` by default):

```bash
juju run opensearch-k8s/leader create-backup -m opensearch
juju run opensearch-k8s/leader list-backups -m opensearch
juju run opensearch-k8s/leader restore backup-id="<id>" -m opensearch
```

### Rotating the key

Export the new key and increment `azure_storage_secret_version`. The module
updates the Juju secret that `azure-storage-integrator` reads.

## Notes

- Both load balancers are internal. They are reachable only from inside the VNet by default.
- Choose `opensearch.constraints` before the first apply.
  Changing it later replaces the application.
- Kubernetes may place several OpenSearch pods on the same node. To keep them on
  different nodes, add a pod anti-affinity rule to the constraints, for example
  `opensearch = { constraints = "tags=anti-pod.app.kubernetes.io/name=opensearch-k8s,anti-pod.topology-key=kubernetes.io/hostname" }`.
  The cluster then needs at least as many nodes as units.
- `self-signed-certificates` is intended for evaluation. Use your organization's
  certificate provider for production deployments (`certificates_integration`).
- COS Lite runs Grafana, Loki and Prometheus on 1G volumes by default. For
  anything beyond a demo, set the `cos` storage directives. See
  [customize storage options](https://documentation.ubuntu.com/observability/latest/how-to/configure-and-tune/customize-storage-options/).
