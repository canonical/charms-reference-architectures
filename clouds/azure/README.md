# Azure Juju Infrastructure
This is a Terraform module facilitating the provisioning of Azure infrastructure for Juju deployments. It uses [azurerm provider](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs) to create the necessary resources.

## Requirements
This module requires the following:
- Terraform to be installed on host machine.
- Azure CLI to be installed and logged in.

## Inputs
The module offers the following configurable inputs:
| Name                      | Type           | Description                                                                                          | Required |
| ------------------------- | -------------- | ---------------------------------------------------------------------------------------------------- | -------- |
| `RESOURCE_GROUP_NAME`     | `string`       | Name of the Azure resource group to create.                                                          | No       |
| `REGION`                  | `string`       | Azure region where resources will be created.                                                        | No       |
| `AZURE_SUBSCRIPTION_ID`   | `string`       | Azure subscription ID for resource creation.                                                         | Yes      |
| `PROVISION_BASTION`       | `bool`         | Whether to provision a bastion host.                                                                 | No       |
| `SSH_PUBLIC_KEY`          | `string`       | Path to the SSH public key for bastion access. (Required if `PROVISION_BASTION` is set to true)      | No       |
| `SOURCE_ADDRESS_PREFIXES` | `list(string)` | List of source address prefixes for NSG rules.                                                       | No       |
| `AKS_CLUSTER_NAME`        | `string`       | Name of the AKS cluster to create. Set to empty string if you don't want to provision an AKS cluster | No       |
| `INITIALIZE_HOST`         | `bool`         | Whether to setup the host machine with juju and the controller                                       | No       |

### Outputs
When applied, the module exports the following outputs:
| Name             | Description                                                                                                                                                                                |
| ---------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `infrastructure` | A map containing the details of the created Azure infrastructure, including resource group, virtual net name, controller subnet name, deployment subnet name, and the bastion's public IP. |
| `aks_cluster`    | A map containing the details of the AKS cluster, including its name, resource group, location, and kubeconfig. (Sensitive)                                                                 |

### Usage
This model stores the Terraform state in an Azure Storage Account. You can use the `clouds/azure/state` module to create the storage account and container for the Terraform state.
To use this module, first ensure you have updated the `backend` section set in your `versions.tf` to match your Azure Storage Account configuration. Then run the following commands in your terminal:

```bash
terraform init
terraform apply -var 'AZURE_SUBSCRIPTION_ID=mySubscriptionId' # Add other variables as needed
```