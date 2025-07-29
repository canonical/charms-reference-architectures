# Terraform module to provision Azure Storage Account for the terraform state backend.
This module creates a storage account and a container to store the Terraform state files.

## Requirements
This module requires the following:
- Terraform to be installed on the host machine.
- Azure CLI to be installed and logged in.

## Inputs
The module offers the following configurable inputs:
| Name                    | Type     | Description                                                           | Required |
| ----------------------- | -------- | --------------------------------------------------------------------- | -------- |
| `RESOURCE_GROUP_NAME`   | `string` | Name of the Azure resource group to create.                           | No       |
| `REGION`                | `string` | Azure region where resources will be created.                         | No       |
| `AZURE_SUBSCRIPTION_ID` | `string` | Azure subscription ID for resource creation.                          | Yes      |
| `STORAGE_ACCOUNT_NAME`  | `string` | Name of the Azure storage account to create. Must be globally unique. | Yes      |

## Outputs
When applied, the module exports the following outputs:
| Name                   | Description                                                                  |
| ---------------------- | ---------------------------------------------------------------------------- |
| `resource_group_name`  | Name of the resource group created for the storage account.                  |
| `storage_account_name` | Name of the storage account created.                                         |
| `container_name`       | Name of the container created within the storage account for Terraform state |

## Usage
To use this module, run the following command in your terminal:

```bash
terraform init
terraform apply -var="RESOURCE_GROUP_NAME=myResourceGroup" -var="REGION=eastus" -var="AZURE_SUBSCRIPTION_ID=mySubscriptionId" -var="STORAGE_ACCOUNT_NAME=myStorageAccount"
```
