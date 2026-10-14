# Valkey on Kubernetes on AWS with TLS, COS Lite and S3 backups

Solution module that composes the [Valkey Kubernetes product module](https://github.com/canonical/valkey-operator/tree/9/edge/terraform/product/k8s)
into a complete stack on EKS. You provide a bucket name, and the module handles the rest.

## Deployed stack

- Model `cos` (set `cos_model` to rename it): [COS Lite](https://github.com/canonical/observability-stack/tree/main/terraform/cos-lite), which
  offers Prometheus remote-write, Loki logging and Grafana dashboards.
- Model `valkey` (set `valkey_model` to rename it):
  - Valkey (3 units) and `data-integrator`, from the product module.
  - `opentelemetry-collector-k8s`, which forwards Valkey metrics, logs and dashboards to the COS
    Lite offers.
  - `self-signed-certificates` on the Valkey `client-certificates` endpoint, which turns on client
    TLS.
  - `s3-integrator` on the Valkey `s3-credentials` endpoint, pointed at the bucket below.
- In AWS:
  - A bucket with all public access blocked.
  - An IAM user with object access to that bucket only, and an access key for it.

## Requirements

| Name      | Version  |
| --------- | -------- |
| terraform | >= 1.11  |
| juju      | >= 2.2.1 |
| aws       | >= 6.0   |

The module reads credentials from the environment:

- Juju: the juju CLI's current controller, or the `JUJU_*` variables. Both models are created on
  that controller, which needs the EKS cluster added as a Kubernetes cloud (`juju add-k8s`).
- AWS: the AWS CLI profile or the `AWS_*` variables. Set the region with `aws_region` or
  `AWS_REGION`. The identity needs permission to create buckets, IAM users, access keys and
  Elastic IPs. With `load_balancer` set, it also needs cluster admin on the EKS cluster through an
  access entry. The identity that created the cluster has it by default.

Terraform stores the generated access key's secret in state. Keep the state in an encrypted remote
backend with restricted access. The key never appears in Juju relation data or in the plan output.

## Usage

```bash
export AWS_REGION=eu-central-1
terraform init
terraform apply -var s3_bucket=my-valkey-backups -var k8s_cloud=k8s
```

Set `k8s_cloud` to the name the EKS cluster has on the controller. A controller bootstrapped on
AWS defaults to the `ec2` cloud, which cannot host these models.

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

### Exposing Valkey outside the cluster

Set `load_balancer` to put the Valkey primary behind an internet-facing Network Load Balancer on
static Elastic IPs. Only the CIDRs you list can reach it:

```bash
terraform apply \
  -var s3_bucket=my-valkey-backups \
  -var k8s_cloud=k8s \
  -var 'load_balancer={allowed_cidrs=["203.0.113.4/32"], eks_cluster="my-cluster", subnet_ids=["subnet-0a...", "subnet-0b..."]}'
terraform output valkey_external_endpoints
```

`subnet_ids` are public subnets (routed to an internet gateway) in the cluster's VPC, at most one
per availability zone. Pick the zones your nodes run in: the NLB only forwards to targets in its
own zone.

The module reserves one Elastic IP per subnet and creates a `LoadBalancer` Service on the TLS port
(6380) that selects the pod the charm labels `role=primary`. It adds the IPs to the server
certificate through `certificate-extra-sans`. Adding it to a running deployment makes the units
request new certificates. The annotations target the NLB support built into EKS, so the cluster
needs no AWS Load Balancer Controller.

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

Increment `s3_key_version`. The module creates a new access key, pushes it to `s3-integrator` and
then deletes the old one.

## Notes

- A new access key can take a few seconds to work. Until it does, the charm can report bucket
  access errors, and it recovers on a later hook.
- The IAM user holds `s3:CreateBucket` on the bucket, because the charm tries to create the bucket
  on start and treats only "already exists" answers as success.
- The bucket is not created with `force_destroy`. `terraform destroy` fails while it still holds
  backups. Empty it first, or remove it from state (`terraform state rm aws_s3_bucket.backups`) to
  keep it.
- COS Lite runs Grafana, Loki and Prometheus on 1G volumes by default, and plans warn about it. For
  anything beyond a demo, see
  [customize storage options](https://documentation.ubuntu.com/observability/latest/how-to/configure-and-tune/customize-storage-options/).
