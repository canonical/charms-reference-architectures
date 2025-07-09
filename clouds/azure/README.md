# Azure Juju Infrastructure Terraform Module

This Terraform module facilitates the provisioning of essential Azure infrastructure components tailored for Juju deployments. It leverages the official [AzureRM provider](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs) to create and manage the necessary cloud resources.

## Features

  * **Resource Group Management**: Creates a dedicated Azure Resource Group to logically organize all provisioned resources.
  * **Networking Configuration**: Sets up a Virtual Network (VNet) with distinct subnets for Juju controllers and deployments, ensuring proper network isolation.
  * **Bastion Host Provisioning**: Optionally provisions a secure bastion host for administrative access to the Juju environment.
  * **Azure Kubernetes Service (AKS) Integration**: Allows for the optional deployment of an AKS cluster, suitable for Juju's Kubernetes integration.
  * **Security Group Rules**: Configures Network Security Group (NSG) rules to control inbound and outbound traffic.
  * **Host Initialization**: Provides an option to set up the host machine with Juju and the controller.

## Requirements

Before using this module, ensure you have the following prerequisites in place:

  * **Terraform**: Version `1.0.0` or higher installed on your host machine.
  * **Azure CLI**: Installed and authenticated (`az login`) with an Azure account that has the necessary permissions to create resources within your target subscription.

## Module Inputs

The module exposes the following configurable input variables.

| Name                      | Type           | Description                                                                                                                                                   | Required                                 | Default         |
| :------------------------ | :------------- | :------------------------------------------------------------------------------------------------------------------------------------------------------------ | :--------------------------------------- | :-------------- |
| `RESOURCE_GROUP_NAME`     | `string`       | Name of the Azure Resource Group to create or use. If left empty, a default name will be used.                                                                | No                                       | `"main-rg"`     |
| `REGION`                  | `string`       | Azure region where all resources will be deployed (e.g., `eastus`, `uksouth`).                                                                                | No                                       | `"eastus"`      |
| `AZURE_SUBSCRIPTION_ID`   | `string`       | Your Azure subscription ID where the resources will be created.                                                                                               | Yes                                      | `n/a`           |
| `PROVISION_BASTION`       | `bool`         | Set to `true` to provision a dedicated bastion host for secure access.                                                                                        | No                                       | `true`          |
| `SSH_PUBLIC_KEY`          | `string`       | The SSH public key content (e.g., `ssh-rsa AAAAB3NzaC...`) used for authenticating to the bastion host.                                                       | **Yes if `PROVISION_BASTION` is `true`** | `null`          |
| `SOURCE_ADDRESS_PREFIXES` | `list(string)` | A list of CIDR blocks (e.g., `["1.2.3.4/32", "5.6.7.0/24"]`) or service tags (e.g., `["VirtualNetwork", "AzureLoadBalancer"]`) allowed for inbound NSG rules. | No                                       | `null`          |
| `AKS_CLUSTER_NAME`        | `string`       | The name of the Azure Kubernetes Service (AKS) cluster to create. Set to an empty string (`""`) if you do not wish to provision an AKS cluster.               | No                                       | `"aks-cluster"` |
| `INITIALIZE_HOST`         | `bool`         | Whether to set up the host machine with Juju and deploy the Juju controller. This typically involves running a remote-exec provisioner.                       | No                                       | `false`         |

---

## Module Outputs

Upon successful application, the module exports the following outputs:


| Name             | Description                                                                                                                                                                                          | Sensitive |
| :--------------- | :--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | :-------- |
| `infrastructure` | A map containing key details of the created Azure infrastructure: `resource_group_name`, `vnet_name`, `controller_subnet_name`, `deployments_subnet_name`, and `bastion_public_ip` (if provisioned). | No        |
| `aks_cluster`    | A map containing details of the provisioned AKS cluster: `name`, `resource_group_name`, `location`, and `kube_config` (the raw kubeconfig content).                                                  | Yes       |

---

## Usage

The `clouds` module is designed to integrate with Terraform's backend configuration for state management. Terraform's state is stored in an Azure Storage Account for collaboration, security, and remote operations.

### 1. Backend Configuration

You can use a separate Terraform module (`clouds/azure/state`) to provision the Azure Storage Account and container required for the Terraform state backend.

```shell
pushd clouds/azure/state
# TODO: change the value set in `storage_account_name` of the backend resource to a bucket name of your choice
tf init 
tf plan -out terraform.out
tf apply terraform.out

popd
```

Ensure you have updated the `backend` section within your `versions.tf` to reflect your Azure Storage Account details you get from the previous step.

Example `versions.tf` snippet for backend configuration:

```terraform
terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~>4.0"
    } 
    random = {
      source  = "hashicorp/random"
      version = "~>3.0"
    }
  }

  # set up backend configuration to use Azure Storage Account
  backend "azurerm" {
    resource_group_name  = "tfstate-rg"
    storage_account_name = "tfstate0axk8vld"
    container_name       = "tfstate"
    key                  = "infra.terraform.tfstate"
  }
}

```

### 2. Setup the azure infrastructure

#### a. Standalone deployment

```shell
pushd clouds/azure

tf init 
tf plan -out terraform.out \
    -var="..." \
    -var="..." \  # optional
    ....
tf apply terraform.out

popd
```

*Note* For sensitive variables like `azure_subscription_id`, it's generally better practice to pass them via environment variables (e.g., `TF_VAR_azure_subscription_id`) or a `terraform.tfvars` file to avoid exposing them directly on the command line in shell history.


#### b. Sourced as a module
To use this module, add a `module` block to your Terraform configuration:

```terraform
module "juju_azure_infra" {
  source = "./clouds/azure/azure-juju-infrastructure" # Adjust path if module is local or use registry source

  azure_subscription_id     = var.azure_subscription_id
  resource_group_name       = var.resource_group_name
  ...
}
```

## License

This module is licensed under the [Apache License](../../LICENSE).

