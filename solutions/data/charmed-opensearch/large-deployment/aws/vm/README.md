# OpenSearch large deployment on AWS machines with OpenSearch Dashboards, TLS, COS Lite and S3 backups

Solution module that composes the
[OpenSearch machine large deployment product module](https://github.com/canonical/opensearch-operator/tree/2/edge/terraform/machine/product/large_deployment)
into a complete stack on EC2. You provide a Kubernetes cloud for COS Lite, and
optionally an S3 bucket for backups, and the module handles the rest.

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
  - With `backups` set, `s3-integrator` pointed at your bucket.
- Each model in `extra_models` (none by default): the OpenSearch apps you place
  there, and its own `opentelemetry-collector`.
- An AWS Network Load Balancer (NLB), private by default, for the OpenSearch Dashboards
  machines. With `dashboards_load_balancer.dns_name`, also a DNS name for it that
  resolves inside the VPC.

Set `cos = null` to deploy without COS Lite and the collectors. No Kubernetes
cloud is then needed. Set `dashboards_load_balancer = null` to skip the NLB.

## Requirements

| Name      | Version |
| --------- | ------- |
| terraform | >= 1.12 |
| juju      | ~> 2.3  |
| aws       | >= 6.0  |

The controller needs the AWS machine cloud as its default cloud, and a
Kubernetes cloud for COS Lite (`juju add-k8s`).

The defaults match the network of this repository's `clouds/aws` module: VPC
`10.0.0.0/16` with public subnets `10.0.10.0/24` and `10.0.11.0/24`. For
another network, set `excluded_subnets` and the `allowed_cidrs` of each app.

The module reads credentials from the environment:

- Juju: the Juju CLI's current controller, or the `JUJU_*` variables.
- AWS: the AWS CLI profile or the `AWS_*` variables. Set `AWS_REGION` to the
  region Juju deploys to. The identity needs permission to manage load
  balancers and target groups, and to read subnets. With
  `dashboards_load_balancer.dns_name`, it also needs to manage Route 53
  private zones. With `public = true` or apps in more than one model, it also
  reads EC2 instances and manages security groups attached to their network
  interfaces.

When an app in `apps` has the `cluster_manager` role, the product module waits for
`failover` with a script that runs `juju` and `jq` on the machine running Terraform,
against the Juju CLI's current controller.

The S3 keys are ephemeral inputs. Terraform does not store them in the plan or
the state. The product module hands them to `s3-integrator` through a Juju secret.

## Usage

```bash
export AWS_REGION=eu-central-1
export TF_VAR_vpc_id="$(juju model-config -m aws:controller vpc-id)"
terraform init
terraform apply
```

With backups, pass an existing bucket and its keys:

```bash
export TF_VAR_s3_access_key=<access key>
export TF_VAR_s3_secret_key=<secret key>
terraform apply -var 'backups={bucket="my-opensearch-backups", region="eu-central-1"}'
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
    constraints = "arch=amd64 cores=8 mem=32G"
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

### Placing apps in other models

Name the models in `extra_models`, and set `model` on `failover` or on an app:

```hcl
extra_models = ["opensearch-failover", "opensearch-data"]
failover     = { model = "opensearch-failover" }
apps         = [{ app_name = "data", config = { roles = "data" }, model = "opensearch-data" }]
```

OpenSearch Dashboards and the integrators deploy to the `opensearch` model.

### Connecting an application

`get-credentials` returns a user and an index for one application.
The endpoints are the private addresses of all OpenSearch units.
Each app accepts connections from its `allowed_cidrs` (the whole VPC by default).
With the `tls-ca` value saved in `ca.pem`:

```bash
curl --cacert ca.pem -u "<username>:<password>" "https://<endpoint>/<index>/_search?q=*"
```

Charms in the `opensearch` model can integrate with the `main`
`opensearch-client` endpoint instead.

### Opening OpenSearch Dashboards

The NLB spreads requests over the OpenSearch Dashboards units. Open the `url` from
`terraform output dashboards_load_balancer` and log in as `admin`, with the
password from `juju run main/leader get-password -m opensearch`.

- `dashboards_load_balancer.dns_name`: a name for OpenSearch Dashboards that
  resolves inside the VPC, for example `dashboards.example.internal`.
- `dashboards_load_balancer.certificate_arn`: the NLB terminates TLS with this
  certificate, imported into AWS Certificate Manager (ACM). It should include
  `dns_name`. Without it, the NLB passes TLS through.
- `opensearch_dashboards.tls = false`: turns off TLS on OpenSearch Dashboards. With
  `certificate_arn`, traffic is then encrypted from browsers to the NLB, and
  unencrypted from the NLB to OpenSearch Dashboards.

The NLB uses TLS to OpenSearch Dashboards only when `certificate_arn` and
`opensearch_dashboards.tls` are both set, and plain TCP otherwise. Switching
between these replaces the NLB's target group, which briefly interrupts
OpenSearch Dashboards traffic.

### Public OpenSearch Dashboards access

With `public = true`, the NLB is internet-facing and accepts only `allowed_cidrs`:

```hcl
dashboards_load_balancer = {
  public          = true
  certificate_arn = "arn:aws:acm:eu-central-1:123456789012:certificate/<certificate-id>"
  subnet_ids      = ["subnet-public-a", "subnet-public-b"]
  allowed_cidrs   = ["203.0.113.5/32"]
  dns_name        = "dashboards.example.com"
}
```

- `certificate_arn`: required. It should include `dns_name`.
- `subnet_ids`: public subnets in `vpc_id`, one per availability zone. They can
  stay in `excluded_subnets`.
- `dns_name`: create a public DNS record pointing it to `address` in the
  `dashboards_load_balancer` output.
  The address changes if you switch between public and private.

### Opening Grafana

On the COS Kubernetes cluster:

```bash
kubectl get svc -n cos traefik-lb -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
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

### Rotating the keys

Export the new keys and increment `s3_secret_version`. The module updates the
Juju secret that `s3-integrator` reads.

## Notes

- The OpenSearch Dashboards NLB is private unless configured for public access.
- `self-signed-certificates` is intended for evaluation. Use your organization's
  certificate provider for production deployments (`certificates_integration`).
- COS Lite runs Grafana, Loki and Prometheus on 1G volumes by default. For
  anything beyond a demo, set the `cos` storage directives. See
  [customize storage options](https://documentation.ubuntu.com/observability/latest/how-to/configure-and-tune/customize-storage-options/).
