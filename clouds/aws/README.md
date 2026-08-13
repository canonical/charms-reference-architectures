# AWS Juju Infrastructure Terraform Module

This Terraform module facilitates the provisioning of essential AWS infrastructure components tailored for Juju deployments. It leverages the official [AWS provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs) to create and manage the necessary cloud resources.

## Features

  * **Networking Configuration**: Sets up a Virtual Private Cloud (VPC) with distinct subnets for Juju controllers and deployments, ensuring proper network isolation.
  * **Bastion Host Provisioning**: Provisions a secure bastion host for administrative access to the Juju environment.
  * **Elastic Kubernetes Cluster (EKS) Integration**: Allows for the optional deployment of an EKS cluster, suitable for Juju's Kubernetes integration.
  * **Host Initialization**: Sets up the bastion host machine with Juju and a machine controller.

## Requirements

Before using this module, ensure you have the following prerequisites in place:

  * **Terraform**: Version `1.6.0` or newer.
  * **AWS CLI v2**: Installed and authenticated on the machine where Terraform is run. Verify the active identity with `aws sts get-caller-identity`.
  * **AWS permissions**: The identity running Terraform must be able to create and delete the resources in this module, including VPC, EC2, IAM, EKS, and S3 resources. For a development environment, an administrator role is the simplest option. For production, use a least-privilege policy covering these resources.
  * **EKS administrator identity**: The AWS credentials supplied through `ACCESS_KEY` and `SECRET_KEY` must belong to the same IAM principal that creates the EKS cluster, or to a principal configured separately through an EKS access entry and `AmazonEKSClusterAdminPolicy`. Juju needs this access to create Kubernetes RBAC resources during `add-k8s`.
  * **EC2 key pair**: An AWS EC2 key pair in the target region and its private key available locally when `PROVISION_BASTION=true`.
  * **Snap support**: The bastion setup installs Juju 3.6 and AWS CLI using Snap. The selected Ubuntu bastion image includes Snap support.

Do not use the EKS service role (`eks-cluster`) as a user credential. That role is assumed by the EKS service. Use an IAM user or role with administrative access to the cluster.

### AWS authentication

Authenticate the AWS CLI before running Terraform and confirm the account and principal:

```shell
aws sts get-caller-identity
```

The module's AWS provider uses the standard AWS credential chain. `ACCESS_KEY` and `SECRET_KEY` are additionally copied to the bastion setup script for Juju and EKS authentication. Treat them as secrets, rotate them if exposed, and avoid placing them directly in shell history.

## Module Inputs

The module exposes the following configurable input variables.

| Name                 | Type           | Description                                                                                                                               | Required                                | Default           |
|:---------------------|:---------------|:------------------------------------------------------------------------------------------------------------------------------------------|:----------------------------------------|:------------------|
| `REGION`             | `string`       | AWS region where all resources will be deployed (e.g., `eu-central-1`).                                                                   | No                                      | `"eu-central-1"`  |
| `SOURCE_ADDRESSES`   | `list(string)` | A list of CIDR blocks (e.g., `["1.2.3.4/32", "5.6.7.0/24"]`) allowed by the bastion's inbound security-group rule.                       | Yes                                     | `null`            |
| `PROVISION_BASTION`  | `bool`         | Set to `true` to provision a dedicated bastion host for secure access.                                                                    | No                                      | `true`            |
| `SSH_KEY`            | `string`       | The name of an existing AWS EC2 key pair used to access the bastion host.                                                                 | Yes                                     | `null`            |
| `SSH_KEY_FILE`       | `string`       | The file path where the AWS SSH key is located.                                                                                           | Yes                                     | `null`            |
| `ACCESS_KEY`         | `string`       | The access key credential for your AWS account (will be used for deploying cloud resources and setting up Juju credentials).              | Yes                                     | `null`            |
| `SECRET_KEY`         | `string`       | The secret key credential for your AWS account (will be used for deploying cloud resources and setting up Juju credentials).              | Yes                                     | `null`            |
| `EKS_CLUSTER_NAME`   | `string`       | The name of the Elastic Kubernetes (EKS) cluster to create. Set to an empty string (`""`) if you do not wish to provision an EKS cluster. | No                                      | `"eks-cluster"`   |
| `SETUP_LOCAL_HOST`   | `bool`         | Whether to set up the local host machine with Juju and deploy the Juju controller.                                                        | No                                      | `false`           |

---

## Module Outputs

Upon successful application, the module exports the following outputs:


| Name             | Description                                                                                                                                                                                    | Sensitive |
|:-----------------|:-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------| :-------- |
| `infrastructure` | A map containing key details of the created AWS infrastructure: `vpc_id`, `controller_subnet_id`, `deployments_subnet_id`, and `bastion_public_ip`.                                            | No        |
| `eks_cluster`    | A map containing details of the provisioned EKS cluster: `name`, `cluster_endpoint`, and `certificate_authority` (Base64 encoded certificate data required to communicate with your cluster).  | Yes       |

---

## Usage

### 1. Backend Configuration

You can use a separate Terraform module (`clouds/aws/state`) to provision the AWS S3 Storage bucket required for the Terraform state backend.

1. Create the bucket where the Terraform state will be saved:

```shell
pushd clouds/aws/state

terraform init 

terraform plan -out terraform.out \
    -var="BUCKET_NAME=myDesiredBucketName"  # required

terraform apply terraform.out

popd
```

2. Update the `backend` section in `clouds/aws/versions.tf` with the bucket name and region, then initialize the backend:

Example `clouds/aws/versions.tf` snippet:

```hcl
terraform {
  # ...
  backend "s3" {
    bucket = "my-bucket-name" # TODO: replace with actual bucket name
    key    = "state"
    region = "eu-central-1"
  }
}
```

```shell
pushd clouds/aws
terraform init -reconfigure
popd
```

Keep the state bucket until all infrastructure managed by the main module has been destroyed.

### 2. Setup the AWS infrastructure

#### Standalone deployment

Prefer environment variables for credentials:

```shell
export TF_VAR_ACCESS_KEY="<your-aws-access-key>"
export TF_VAR_SECRET_KEY="<your-aws-secret-key>"
```

```shell
pushd clouds/aws

terraform init 

terraform plan -out terraform.out \
  -var="REGION=eu-central-1" \
  -var='SOURCE_ADDRESSES=["123.45.67.12/32"]' \
  -var="PROVISION_BASTION=true" \
  -var="SSH_KEY=aws-key" \
  -var="SSH_KEY_FILE=/home/example/.ssh/aws-key.pem" \
  -var="EKS_CLUSTER_NAME=my-eks-cluster" \
  -var="SETUP_LOCAL_HOST=false"

terraform apply terraform.out

popd
```

`SOURCE_ADDRESSES`, `SSH_KEY`, and `SSH_KEY_FILE` are required by the current variable definitions even when their associated optional feature is disabled. Use an absolute path for `SSH_KEY_FILE`; Terraform does not expand `~` in every context.

EKS control-plane creation commonly takes 10–15 minutes and can sometimes take up to 30 minutes. Repeated `Still creating...` messages during that interval are expected.

### EKS access and Juju

The EKS resource enables API access and grants cluster-administrator permissions to the principal that creates the cluster. The credentials passed as `ACCESS_KEY` and `SECRET_KEY` must therefore resolve to that same principal unless an explicit EKS access entry has been configured.

Compare the identities before applying:

```shell
aws sts get-caller-identity

AWS_ACCESS_KEY_ID="$TF_VAR_ACCESS_KEY" \
AWS_SECRET_ACCESS_KEY="$TF_VAR_SECRET_KEY" \
aws sts get-caller-identity
```

If these identities differ, create an EKS access entry for the second IAM user or role and associate `AmazonEKSClusterAdminPolicy`. Use the IAM user or role ARN, not an STS assumed-role session ARN.

The bastion setup performs the following steps automatically:

1. Installs Juju 3.6 and AWS CLI.
2. Creates `/home/ubuntu/.kube/config` with `aws eks update-kubeconfig`.
3. Bootstraps the machine controller named `aws` if it does not already exist.
4. Registers EKS as the `k8s` cloud on that controller.

Juju 3.x is strictly confined. For EKS, only `add-k8s` is run with Canonical's raw client path:

```shell
/snap/juju/current/bin/juju add-k8s k8s --client --controller aws
```

This allows the EKS kubeconfig authentication plugin to execute AWS CLI. Other Juju commands use the normal `/snap/bin/juju` launcher.

### Rerunning bastion setup

Terraform does not rerun provisioners merely because `setup-juju-env.tftpl` changed. Force replacement of the setup resource:

```shell
terraform apply -replace='null_resource.set_up_bastion_script[0]'
```

To recreate the bastion and rerun its setup without recreating EKS:

```shell
terraform apply \
  -replace='aws_instance.bastion_host[0]' \
  -replace='null_resource.set_up_bastion_script[0]'
```

The setup script detects an existing controller named `aws` and skips bootstrapping it again.

### Troubleshooting

`BucketAlreadyExists` means the S3 name is registered globally, possibly by another account. Select a different, globally unique name and regenerate the saved plan.

`Unauthorized` from `juju add-k8s` means the AWS principal generating the EKS token lacks Kubernetes access. Confirm the identity with `aws sts get-caller-identity` and configure an EKS access entry and cluster-admin access policy when it is not the cluster creator.

`EntityAlreadyExists` for an IAM role means a role with the configured name already exists outside the current Terraform state. Import it if it belongs to this deployment, or use a unique role name; do not delete an unknown role.

### Destroying the deployment

Destroy the main infrastructure before deleting the state bucket:

```shell
terraform plan -destroy -out=destroy.out
terraform apply destroy.out
```

Verify the active backend and workspace with `terraform state list` and `terraform workspace show` before approving the destroy plan.

## License

This module is licensed under the [Apache License](../../LICENSE).
