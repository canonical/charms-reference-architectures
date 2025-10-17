# Terraform module to provision AWS S3 Storage for the terraform state backend.
This module creates an S3 storage bucket to store the Terraform state files.

## Requirements
This module requires the following:
- Terraform to be installed on the host machine.

## Inputs
The module offers the following configurable inputs:
| Name                 | Type     | Description                                                  | Required |
| -------------------- | -------- | ------------------------------------------------------------ | -------- |
| `REGION`             | `string` | AWS region where resources will be created.                  | No       |
| `ACCESS_KEY`         | `string` | The access key credential for the AWS account.               | Yes      |
| `SECRET_KEY`         | `string` | The secret key credential for your AWS account.              | Yes      |
| `BUCKET_NAME`        | `string` | The name of the S3 storage bucket to create.                 | Yes      |

## Outputs
The module does not provide any outputs.

## Usage
To use this module, run the following command in your terminal:

```bash
terraform init
terraform apply \
  -var="REGION=eu-central-1" \
  -var="BUCKET_NAME=<your-desired-bucket-name>"
```
