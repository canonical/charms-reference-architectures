# AWS Juju Infrastructure Terraform Module

This Terraform module facilitates the provisioning of essential AWS infrastructure components tailored for Juju deployments. It leverages the official [AWS provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs) to create and manage the necessary cloud resources.

## Features

  * **Networking Configuration**: Sets up a Virtual Private Cloud (VPC) with distinct subnets for Juju controllers and deployments, ensuring proper network isolation.
  * **Bastion Host Provisioning**: Provisions a secure bastion host for administrative access to the Juju environment.
  * **Host Initialization**: Sets up the bastion host machine with Juju and a machine controller.

## Requirements

Before using this module, ensure you have the following prerequisites in place:

  * **Terraform**: Version `1.0.0` or higher installed on your host machine.
  * **AWS CLI**: Installed and authenticated with an AWS account that has the necessary permissions to create resources within your target subscription.

## Module Inputs

The module exposes the following configurable input variables.

| Name               | Type           | Description                                                                                                                  | Required | Default          |
|:-------------------|:---------------|:-----------------------------------------------------------------------------------------------------------------------------|:---------|:-----------------|
| `REGION`           | `string`       | AWS region where all resources will be deployed (e.g., `eu-central-1`).                                                      | No       | `"eu-central-1"` |
| `SOURCE_ADDRESSES` | `list(string)` | A list of CIDR blocks (e.g., `["1.2.3.4/32", "5.6.7.0/24"]`) to be allowed for inbound NSG rules.                            | Yes      | `null`           |
| `SSH_KEY`          | `string`       | The AWS SSH private key used to access the bastion host.                                                                     | Yes      | `null`           |
| `SSH_KEY_FILE`     | `string`       | The file path where the AWS SSH key is located.                                                                              | Yes      | `null`           |
| `ACCESS_KEY`       | `string`       | The access key credential for your AWS account (will be used for deploying cloud resources and setting up Juju credentials). | Yes      | `null`           |
| `SECRET_KEY`       | `string`       | The secret key credential for your AWS account (will be used for deploying cloud resources and setting up Juju credentials). | Yes      | `null`           |

---

## Module Outputs

Upon successful application, the module exports the following outputs:


| Name             | Description                                                                                                                                                   | Sensitive |
| :--------------- |:--------------------------------------------------------------------------------------------------------------------------------------------------------------| :-------- |
| `infrastructure` | A map containing key details of the created AWS infrastructure: `vpc_id`, `controller_subnet_id`, `deployments_subnet_id`, and `bastion_public_ip`.           | No        |

---

## Usage

### Setup the azure infrastructure

#### a. Standalone deployment

```shell
pushd clouds/aws

terraform init 

terraform plan -out terraform.out \
    -var="REGION=eastus"                          \  # optional, defaults to "eu-central-1"
    -var='SOURCE_ADDRESSES=["123.45.67.12/32"]'   \  # required, put your host's (Public) IP address to be allowed to ssh into the Bastion
    -var="SSH_KEY=aws-key"                        \  # required, the name of your AWS SSH private key to ssh into the Bastion
    -var="SSH_KEY_FILE=~/.ssh/aws-key.pem"        \  # required, the path to your AWS SSH private key to ssh into the Bastion
    -var="ACCESS_KEY=<your-aws-access-key>"       \  # required, the access key for AWS account
    -var="SECRET_KEY=<your-aws-secret-key>"       \  # required, the secret key for AWS account

terraform apply terraform.out

popd
```

*Note* For sensitive variables like `ACCESS_KEY`, it's generally better practice to pass them via environment variables (e.g., `TF_VAR_ACCESS_KEY`) or a `terraform.tfvars` file to avoid exposing them directly on the command line in shell history.

## License

This module is licensed under the [Apache License](../../LICENSE).

