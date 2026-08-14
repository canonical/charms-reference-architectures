# AWS Juju Infrastructure Terraform Module

This Terraform module facilitates the provisioning of essential AWS infrastructure components tailored for Juju deployments. It leverages the official [AWS provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs) to create and manage the necessary cloud resources.

## How it works

The deployment is split into two Terraform root modules with separate lifecycles:

1. The `clouds/aws/state` module is applied first. It creates a private S3 bucket that will hold the Terraform state for the AWS environment. Because this bucket does not exist yet, the state module uses local state while bootstrapping it.
2. The bucket name and region are then added to the S3 backend configuration in `clouds/aws/versions.tf`. Running `terraform init` from `clouds/aws` connects the main module to that remote backend.
3. The main `clouds/aws` module is applied to deploy the selected cloud environment, including its networking, optional bastion host, optional EKS cluster, and Juju setup. Terraform records these resources in the S3 state bucket so subsequent plans and applies use the same source of truth.

The state bucket must remain available for the entire lifetime of the environment. When removing a deployment, destroy the resources managed by the main module first and remove the state bucket only afterward.

## Features

  * **Networking Configuration**: Sets up a Virtual Private Cloud (VPC) with distinct subnets for Juju controllers and deployments, ensuring proper network isolation.
  * **Bastion Host Provisioning**: Provisions a secure bastion host for administrative access to the Juju environment.
  * **Elastic Kubernetes Cluster (EKS) Integration**: Allows for the optional deployment of an EKS cluster, suitable for Juju's Kubernetes integration.
  * **Host Initialization**: Sets up the bastion host machine with Juju and a machine controller.

## Requirements

Before using this module, ensure you have the following prerequisites in place:

  * **Terraform**: Version `1.6.0` or newer.
  * **AWS CLI v2**: Installed and authenticated on the machine where Terraform is run. Verify the active identity with `aws sts get-caller-identity`.
  * **AWS permissions**: The identity running Terraform must be able to create and delete the resources in this module, including VPC, EC2, IAM, EKS, and S3 resources. For a development environment, an `AdministratorAccess` policy is the simplest option. For production, use a least-privilege policy covering these resources.
  * **EC2 key pair**: An AWS EC2 key pair in the target region and its private key available locally when `PROVISION_BASTION=true`.

### AWS authentication

Authenticate the AWS CLI before running Terraform and confirm the account and principal:

```shell
aws sts get-caller-identity
```

## Module Inputs

The module exposes the following configurable input variables.

| Name                      | Type           | Description                                                                                                                               | Required                                | Default           |
|:--------------------------|:---------------|:------------------------------------------------------------------------------------------------------------------------------------------|:----------------------------------------|:------------------|
| `REGION`                  | `string`       | AWS region where all resources will be deployed (e.g., `eu-central-1`).                                                                   | No                                      | `"eu-central-1"`  |
| `SOURCE_ADDRESSES`        | `list(string)` | A list of CIDR blocks (e.g., `["1.2.3.4/32", "5.6.7.0/24"]`) to be allowed by the bastion's inbound NSG rules.                                         | Yes                                     | `null`            |
| `PROVISION_BASTION`       | `bool`         | Set to `true` to provision a dedicated bastion host for secure access.                                                                    | No                                      | `true`            |
| `SSH_KEY`                 | `string`       | The name of an existing AWS EC2 key pair used to access the bastion host.host.                                                                                  | Yes                                     | `null`            |
| `SSH_KEY_FILE`            | `string`       | The file path where the AWS SSH key is located.                                                                                           | Yes                                     | `null`            |
| `ACCESS_KEY`              | `string`       | The access key credential for your AWS account (will be used for deploying cloud resources and setting up Juju credentials).              | Yes                                     | `null`            |
| `SECRET_KEY`              | `string`       | The secret key credential for your AWS account (will be used for deploying cloud resources and setting up Juju credentials).              | Yes                                     | `null`            |
| `EKS_CLUSTER_NAME`        | `string`       | The name of the Elastic Kubernetes (EKS) cluster to create. Set to an empty string (`""`) if you do not wish to provision an EKS cluster. | No                                      | `"eks-cluster"`   |
| `EKS_NODE_INSTANCE_TYPES` | `list(string)` | EC2 instance types used by the EKS managed node group. | No | `["m6i.xlarge"]` |
| `SETUP_LOCAL_HOST`        | `bool`         | Whether to set up the local host machine with Juju and deploy the Juju controller.                                                        | No                                      | `false`           |

---

## Module Outputs

Upon successful application, the module exports the following outputs:


| Name             | Description                                                                                                                                                                                    | Sensitive |
|:-----------------|:-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------| :-------- |
| `infrastructure` | A map containing key details of the created AWS infrastructure: `vpc_id`, `controller_subnet_id`, `deployments_subnet_id`, and `bastion_public_ip`.                                            | No        |
| `eks_cluster`    | A map containing details of the provisioned EKS cluster and managed node group: `name`, `cluster_endpoint`, `certificate_authority`, `node_group_name`, and `node_role_arn`. | Yes |

---

## Usage

### 1. Backend Configuration

You can use a separate Terraform module (`clouds/aws/state`) to provision the AWS S3 Storage bucket required for the Terraform state backend.

1. Create the bucket where the terraform state will be saved.

```shell
pushd clouds/aws/state

terraform init 

terraform plan -out terraform.out \
    -var="BUCKET_NAME=myDesiredBucketName"  # required

terraform apply terraform.out

popd
```

The default region is `eu-central-1`. To use a different region, add the REGION variable to the previous command:

```
    -var="REGION=eu-west-1"
```

2. Once that's done, update the `backend` section within your `clouds/aws/versions.tf` file to reflect your AWS S3 Storage bucket name you get from the previous step.

Example `clouds/aws/versions.tf` snippet for backend configuration:

```hcl
terraform {
  ...
  required_providers {
    ...
  }

  # set up backend configuration to use AWS S3 storage bucket
  backend "s3" {
    bucket = "my-bucket-name" # TODO: replace with actual bucket name
    key    = "state"
    region = "eu-central-1"   # TODO: replace with actual region is needed
    }
}
```

Keep the state bucket until all infrastructure managed by the main module has been destroyed.

### 2. Setup the AWS infrastructure

#### Standalone deployment

Export the credentials from your active AWS CLI profile for use by Terraform:

```shell
export TF_VAR_ACCESS_KEY="$(aws configure get aws_access_key_id)"
export TF_VAR_SECRET_KEY="$(aws configure get aws_secret_access_key)"
```

Or use a `terraform.tfvars` to avoid exposing them directly on the command line in shell history.

```shell
pushd clouds/aws

terraform init 

terraform plan -out terraform.out \
    -var="REGION=eu-central-1"                    \  # optional, defaults to "eu-central-1"
    -var='SOURCE_ADDRESSES=["123.45.67.12/32"]'   \  # required, put your host's (Public) IP address to be allowed to ssh into the environment
    -var="PROVISION_BASTION=true"                 \  # optional, defaults to true
    -var="SSH_KEY=aws-key"                        \  # required, the name of your AWS SSH private key to ssh into the Bastion
    -var="SSH_KEY_FILE=~/.ssh/aws-key.pem"        \  # required, the path to your AWS SSH private key to ssh into the Bastion
    -var="EKS_CLUSTER_NAME=myEKSCluster"          \  # optional, defaults to "eks-cluster", set to "" if you do not want to provision an EKS cluster
    -var="SETUP_LOCAL_HOST=false"                 \  # optional, defaults to false, set to true if you don't want a bastion and you want to set up the local host with Juju and deploy the controller

terraform apply terraform.out

popd
```

### Destroying the deployment

Destroy the main infrastructure before deleting the state bucket:

```shell
terraform plan -destroy -out=destroy.out
terraform apply destroy.out
```

Verify the active backend and workspace with `terraform state list` and `terraform workspace show` before approving the destroy plan.

## License

This module is licensed under the [Apache License](../../LICENSE).
