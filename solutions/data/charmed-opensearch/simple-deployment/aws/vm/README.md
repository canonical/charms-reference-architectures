# OpenSearch on AWS machines with Dashboards, TLS, COS Lite and S3 backups

Solution module that composes the
[OpenSearch machine simple deployment product module](https://github.com/canonical/opensearch-operator/tree/7e51f6ff6ab2b1b2a3de9f39fd58b5b64eff622b/terraform/machine/product/simple_deployment)
into a complete stack on EC2. You provide a Kubernetes cloud for COS Lite, and
optionally an S3 bucket for backups, and the module handles the rest.

## Deployed stack

- Model `cos` on `cos.cloud` (set `cos.model` to rename it):
  [COS Lite](https://github.com/canonical/observability-stack/tree/tf-cos-lite-3.0.3/terraform/cos-lite),
  which offers Prometheus remote-write, Loki logging and Grafana dashboards.
  Its Traefik gets an internal Network Load Balancer (NLB).
- Model `opensearch` on the controller's default cloud (set `opensearch_model`
  to rename it):
  - OpenSearch (3 units), OpenSearch Dashboards (3 units), `data-integrator`
    and `self-signed-certificates`, from the product module.
  - The `opentelemetry-collector` subordinate on each OpenSearch and Dashboards
    machine, which forwards metrics, logs and dashboards to the COS Lite
    offers.
  - With `backups` set, `s3-integrator` pointed at your bucket.
- An internal AWS Network Load Balancer (NLB) for the OpenSearch Dashboards
  machines. With `dashboards_load_balancer.dns_name`, also a private Route 53
  name for it.

Set `cos = null` to deploy without COS Lite and the collector. No Kubernetes
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
another network, set `excluded_subnets` and the `allowed_cidrs` of OpenSearch
and Dashboards.

The module reads credentials from the environment:

- Juju: the juju CLI's current controller, or the `JUJU_*` variables.
- AWS: the AWS CLI profile or the `AWS_*` variables. Set `AWS_REGION` to the
  region Juju deploys to. The identity needs permission to manage load
  balancers and target groups, and to read subnets. With
  `dashboards_load_balancer.dns_name`, it also needs to manage Route 53
  private zones.

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

Charm options go in `config`, for example:

```hcl
opensearch = {
  units              = 5
  config             = { profile = "production" }
  constraints        = "arch=amd64 cores=8 mem=32G"
  storage_directives = { opensearch-data = "200G" }
}
```

After apply:

```bash
# Client credentials: endpoints, user, password, index and CA.
juju run data-integrator/leader get-credentials -m opensearch

# admin password
juju run opensearch/leader get-password -m opensearch

# Dashboards URL.
terraform output dashboards_load_balancer

# Grafana admin password.
juju run grafana/leader get-admin-password -m cos
```

### Connecting an application

`get-credentials` returns a user and an index for one application.
The endpoints are the private addresses of all OpenSearch units, on port 9200.
OpenSearch accepts connections from `opensearch.allowed_cidrs`, the whole VPC
by default. With the `tls-ca` value saved in `ca.pem`:

```bash
curl --cacert ca.pem -u "<username>:<password>" "https://<endpoint>/<index>/_search?q=*"
```

Charms in the `opensearch` model can integrate with the `opensearch`
`opensearch-client` endpoint instead.

### Opening Dashboards

The NLB spreads requests over the Dashboards units. Open the `url` from
`terraform output dashboards_load_balancer` and log in as `admin`, with the
password from `juju run opensearch/leader get-password -m opensearch`.

- `dashboards_load_balancer.dns_name`: a private Route 53 zone and a record that
  points this name at the NLB. The `url` output then uses this name.
- `dashboards_load_balancer.certificate_arn`: the NLB terminates TLS with this
  certificate, imported into AWS Certificate Manager (ACM). It should include
  `dns_name`. Without it, the NLB passes TLS through and Dashboards shows its
  own certificate.
- `opensearch_dashboards.tls = false`: turns off TLS on Dashboards. With
  `certificate_arn`, traffic is then encrypted from browsers to the NLB, and
  unencrypted from the NLB to Dashboards.

The NLB uses TLS to Dashboards only when `certificate_arn` and
`opensearch_dashboards.tls` are both set, and plain TCP otherwise. Switching
between these replaces the NLB's target group, which briefly interrupts
Dashboards traffic.

### Opening Grafana

On the COS Kubernetes cluster:

```bash
kubectl get svc -n cos traefik-lb -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
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

### Rotating the keys

Export the new keys and increment `s3_secret_version`. The module updates the
Juju secret that `s3-integrator` reads.

## Notes

- Both NLBs are internal. They are reachable only from inside the VPC by default.
- Choose `opensearch.constraints` and `opensearch.storage_directives` before
  the first apply. Changing them later replaces the application. The
  `production` profile needs more memory than the default `testing` profile.
- COS Lite runs Grafana, Loki and Prometheus on 1G volumes by default. For
  anything beyond a demo, set the `cos` storage directives. See
  [customize storage options](https://documentation.ubuntu.com/observability/latest/how-to/configure-and-tune/customize-storage-options/).
