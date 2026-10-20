# OpenSearch large deployment on Kubernetes on Azure with OpenSearch Dashboards, TLS, COS Lite and Azure Storage backups

Solution module that composes the
[OpenSearch Kubernetes large deployment product module](https://github.com/canonical/opensearch-operator/tree/2/edge/terraform/kubernetes/product/large_deployment)
into a complete stack on AKS. You provide the AKS cluster, and optionally an Azure storage
container for backups, and the module handles the rest.

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
  - `traefik-k8s` in front of OpenSearch Dashboards, with an internal Azure load balancer.
  - `opentelemetry-collector-k8s`, which forwards metrics, logs and dashboards
    to the COS Lite offers.
  - With `backups` set, `azure-storage-integrator` pointed at your container.
- Each model in `extra_models` (none by default): the OpenSearch apps you place
  there, and its own `opentelemetry-collector-k8s`.
- A DaemonSet, `os-node-settings-<opensearch_model>` in `kube-system`, which sets
  the kernel settings OpenSearch needs on every AKS node.

Set `cos = null` to deploy without COS Lite and the collectors.

## Requirements

| Name       | Version |
| ---------- | ------- |
| terraform  | >= 1.12 |
| juju       | ~> 2.2  |
| kubernetes | ~> 3.0  |

The controller needs the AKS cluster added as a Kubernetes cloud
(`juju add-k8s`). All models are created on it.

OpenSearch needs `vm.swappiness = 0` and `vm.max_map_count` of at least 262144
on the AKS nodes. The DaemonSet sets both on every node, so the module also
needs access to the cluster.

With this repository's `clouds/azure` module, set
`AKS_SUBNET_NETWORK_CONTRIBUTOR=true`, so that AKS can create the internal load
balancers.

The module reads credentials from the environment:

- Juju: the Juju CLI's current controller, or the `JUJU_*` variables.
- Kubernetes: `KUBE_CONFIG_PATH`, the AKS cluster's kubeconfig.

When an app in `apps` has the `cluster_manager` role, the product module waits for
`failover` with a script that runs `juju` and `jq` on the machine running Terraform,
against the Juju CLI's current controller.

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

### Placing apps in other models

Name the models in `extra_models`, and set `model` on `failover` or on an app:

```hcl
extra_models = ["opensearch-failover", "opensearch-data"]
failover     = { model = "opensearch-failover" }
apps         = [{ app_name = "data", config = { roles = "data" }, model = "opensearch-data" }]
```

OpenSearch Dashboards, Traefik and the integrators deploy to the `opensearch` model.

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
(`opensearch-k8s-ld` by default):

```bash
juju run main/leader create-backup -m opensearch
juju run main/leader list-backups -m opensearch
juju run main/leader restore backup-id="<id>" -m opensearch
```

### Rotating the key

Export the new key and increment `azure_storage_secret_version`. The module
updates the Juju secret that `azure-storage-integrator` reads.

## Notes

- Both load balancers are internal. They are reachable only from inside the VNet by default.
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
