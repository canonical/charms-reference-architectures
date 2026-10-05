# Valkey on AWS machines with TLS, COS Lite and S3 backups

Solution module that composes the [Valkey machine product module](https://github.com/canonical/valkey-operator/tree/dpe-10797-charm-product-tf-modules/terraform/product/vm) into a
complete stack on EC2. You provide a bucket name and the name of a Kubernetes cloud for COS Lite,
and the module handles the rest.

## Deployed stack

- Model `cos` on `k8s_cloud` (set `cos_model` to rename it): [COS Lite](https://github.com/canonical/observability-stack/tree/main/terraform/cos-lite),
  which offers Prometheus remote-write, Loki logging and Grafana dashboards.
- Model `valkey` on the controller's default cloud or `machine_cloud` (set `valkey_model` to rename
  it). The example creates it and hands it to the product module:
  - Valkey (3 units, one machine each) and `data-integrator`, from the product module.
  - The `opentelemetry-collector` subordinate on each Valkey machine, which forwards Valkey
    metrics, logs and dashboards to the COS Lite offers.
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

The controller needs a machine cloud for Valkey and a Kubernetes cloud for COS Lite. For example,
bootstrap on AWS and add an EKS cluster with `juju add-k8s`.

The module reads credentials from the environment:

- Juju: the juju CLI's current controller, or the `JUJU_*` variables. Both models are created on
  that controller.
- AWS: the AWS CLI profile or the `AWS_*` variables. Set the region with `aws_region` or
  `AWS_REGION`. The identity needs permission to create buckets, IAM users and access keys, and to
  read subnets.

Terraform stores the generated access key's secret in state. Keep the state in an encrypted remote
backend with restricted access. The key never appears in Juju relation data or in the plan output.

## Usage

```bash
export AWS_REGION=eu-central-1
terraform init
terraform apply -var s3_bucket=my-valkey-backups -var k8s_cloud=k8s
```

The COS model uses the controller credential named like `k8s_cloud`, which is the name
`juju add-k8s` gives it. If yours differs, set `k8s_credential`. `juju credentials --controller
<controller>` lists them.

The Valkey model goes on the controller's default cloud. When that cloud is not the machine cloud
you want, set `machine_cloud`, and `machine_credential` if the cloud has more than one credential.

After apply:

```bash
# Client credentials. Clients must connect with TLS and trust the self-signed CA.
juju run data-integrator/leader get-credentials -m valkey
juju run self-signed-certificates/leader get-ca-certificate -m valkey

# Grafana admin password, for the dashboards Valkey ships.
juju run grafana/leader get-admin-password -m cos
```

### Connecting from outside AWS

Set `external_access` to reach Valkey on the units' public IPs. Juju exposes Valkey and opens its
TLS ports, 6380 and 26380, in the machines' security group, only to the CIDRs you list.

A machine gets a usable public IP only in a public subnet, and by default Juju places machines in
any subnet of the VPC. So `vpc_id` names the VPC the controller puts models in (its `vpc-id` model
config). The module moves that VPC's private subnets (those that don't map a public IP on launch)
into a separate space in the Valkey model, and sets the model constraint `spaces=alpha`. Every
machine in the model then lands in a public subnet of the default space.

AWS assigns the public IPs when it creates the machines, so this takes two applies. Expose Valkey
first:

```bash
terraform apply \
  -var s3_bucket=my-valkey-backups \
  -var k8s_cloud=k8s \
  -var 'external_access={allowed_cidrs=["203.0.113.4/32"], vpc_id="vpc-0123456789abcdef0"}'
juju status valkey -m valkey   # the Public address column
```

Then add the public IPs to the server certificates through `certificate-extra-sans`. The units
request new certificates, and every certificate lists all the IPs:

```bash
terraform apply \
  -var s3_bucket=my-valkey-backups \
  -var k8s_cloud=k8s \
  -var 'external_access={allowed_cidrs=["203.0.113.4/32"], vpc_id="vpc-0123456789abcdef0", extra_sans=["<ip0>","<ip1>","<ip2>"]}'
```

Connect with the CA from `self-signed-certificates` and the credentials from `data-integrator`:

```bash
valkey-cli -h <primary public ip> -p 6380 --tls --cacert ca.pem --user <username> --pass <password>
```

- Clients connect in standalone mode, not Sentinel mode. On machines, Sentinel announces the
  units' private IPs, which an outside client cannot reach.
- Writes go to the primary only. Run `ROLE` to see which unit you reached. After a failover,
  reconnect to the new primary's public IP.
- The public IPs are ephemeral. If a machine is stopped and started, AWS gives it a new one, so
  update `extra_sans` to match.
- `get-credentials` still reports the private endpoints.
- Set `external_access` before the first apply. Machines that already run in a private subnet stay
  there.

### Rotating the key

Increment `s3_key_version`. The module creates a new access key, pushes it to `s3-integrator` and
then deletes the old one.

## Notes

- The collector pushes metrics and logs to the addresses COS Lite advertises through Traefik, so
  the Valkey machines must reach Traefik's address. On EKS, Traefik's `LoadBalancer` Service gets
  a public load balancer that machines with outbound internet access can reach.
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
- The Valkey model and the COS model sit on the same controller, so the collector reaches COS
  through cross-model relations on the offers the COS Lite module creates.
