# Azure Juju Infrastructure Terraform Module

This Terraform module facilitates the provisioning of essential Azure infrastructure components tailored for Juju deployments. It leverages the official [AzureRM provider](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs) to create and manage the necessary cloud resources.

## How it works

The deployment is split into two Terraform root modules with separate lifecycles:

1. The `clouds/azure/state` module creates a resource group, an Azure Storage Account, and a private blob container for the environment's Terraform state. Because these resources do not exist yet, this module uses local state to bootstrap them.
2. The `clouds/azure` module deploys the resource group, networking, optional bastion host, optional AKS cluster, and Juju setup. It uses the blob container created by the state module as its remote backend. Configure the `azurerm` backend in `clouds/azure/versions.tf` with the state module's outputs before running `terraform init` for this module.

The storage account and blob container must remain available for the entire lifetime of the environment. When removing a deployment, destroy the resources managed by the main module first, then destroy the state module's resources.

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

| Name                    | Type           | Description                                                                                                                                                   | Required                                 | Default         |
| :---------------------- | :------------- | :------------------------------------------------------------------------------------------------------------------------------------------------------------ | :--------------------------------------- | :-------------- |
| `RESOURCE_GROUP_NAME`   | `string`       | Name of the Azure Resource Group to create or use. If left empty, a default name will be used.                                                                | No                                       | `"main-rg"`     |
| `REGION`                | `string`       | Azure region where all resources will be deployed (e.g., `eastus`, `uksouth`).                                                                                | No                                       | `"eastus"`      |
| `AZURE_SUBSCRIPTION_ID` | `string`       | Your Azure subscription ID where the resources will be created.                                                                                               | Yes                                      | `n/a`           |
| `PROVISION_BASTION`     | `bool`         | Set to `true` to provision a dedicated bastion host for secure access.                                                                                        | No                                       | `true`          |
| `SSH_PUBLIC_KEY`        | `string`       | Path to the SSH public key used to access the bastion.                                                                                                        | **Yes if `PROVISION_BASTION` is `true`** | `null`          |
| `SSH_PRIVATE_KEY`       | `string`       | Path to the SSH private key used to access the bastion.                                                                                                       | **Yes if `PROVISION_BASTION` is `true`** | `null`          |
| `SOURCE_ADDRESSES`      | `list(string)` | A list of CIDR blocks (e.g., `["1.2.3.4/32", "5.6.7.0/24"]`) or service tags (e.g., `["VirtualNetwork", "AzureLoadBalancer"]`) allowed for inbound NSG rules. | No                                       | `null`          |
| `AKS_CLUSTER_NAME`      | `string`       | The name of the Azure Kubernetes Service (AKS) cluster to create. Set to an empty string (`""`) if you do not wish to provision an AKS cluster.               | No                                       | `"aks-cluster"` |
| `AKS_NODE_COUNT`        | `number`       | Number of nodes in the default AKS node pool.                                                                                                                  | No                                       | `3`             |
| `AKS_NODE_VM_SIZE`      | `string`       | VM size for the default AKS node pool. The default supports persistent workloads requiring a high Azure Disk attachment count.                                | No                                       | `"Standard_D16s_v3"` |
| `SETUP_LOCAL_HOST`      | `bool`         | Whether to set up the host machine with Juju and deploy the Juju controller. This typically involves running a remote-exec provisioner.                       | No                                       | `false`         |
| `CONTROLLER_CONSTRAINTS` | `string`      | Juju constraints used to provision the controller machine.                                                                                                    | No                                       | `"cores=4 mem=8G"` |

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

1. Create the azure storage account where the terraform state will be saved
```shell
pushd clouds/azure/state

terraform init 

terraform plan -out terraform.out \
    -var="AZURE_SUBSCRIPTION_ID=mySubscriptionId"  # required, your Azure subscription ID

terraform apply terraform.out

popd
```

To customize resource group and and the the storage account name prefix, set `RESOURCE_GROUP_NAME` and `STORAGE_ACCOUNT_NAME` when planning the state module.

```shell
-var="RESOURCE_GROUP_NAME=new-resourge-group"
-var="STORAGE_ACCOUNT_NAME=tfstateuniquetest"
```

The module always appends a random suffix to ensure that the storage account name is unique. If this variable is omitted, the prefix defaults to `tfstate`.

Save the output values, you will use them in the next step.

2. Once that's done, copy the `storage_account_name` output variable.
3. Update the `backend` section within your `clouds/azure/versions.tf` file to reflect your Azure Storage Account details you get from the previous step.

Example `clouds/azure/versions.tf` snippet for backend configuration:
```
  terraform {
    ...
    required_providers {
      ...
    }
    
    # set up backend configuration to use Azure Storage Account
    backend "azurerm" {
        ...
        storage_account_name = "tfstate8lbos2zx" # TODO replace this with a valid storage account name
        resource_group_name  = "tfstate-rg"      # TODO replace if customized in the previous step
        ...
      }
  }
```

### 2. Setup the azure infrastructure

#### a. Standalone deployment

```shell
pushd clouds/azure

terraform init 

terraform plan -out terraform.out \
    -var="RESOURCE_GROUP_NAME=myResourceGroup"    \  # optional, defaults to "main-rg". Use a different name from the state resource group
    -var="REGION=eastus"                          \  # optional, defaults to "eastus
    -var="AZURE_SUBSCRIPTION_ID=mySubscriptionId" \  # required, your Azure subscription ID
    -var="PROVISION_BASTION=true"                 \  # optional, defaults to true
    -var="SSH_PUBLIC_KEY=~/.ssh/id_rsa.pub"       \  # required ONLY IF PROVISION_BASTION is true, your SSH public key to be stored in the Bastion
    -var="SSH_PRIVATE_KEY=~/.ssh/id_rsa"          \  # required ONLY IF PROVISION_BASTION is true, your SSH private key to ssh into the Bastion
    -var='SOURCE_ADDRESSES=["123.45.67.12/32"]'   \  # optional, put your host's (Public) IP address to be allowed to ssh into the Bastion, defaults to null/[0.0.0.0/0]
    -var="AKS_CLUSTER_NAME=myAKSCluster"          \  # optional, defaults to "aks-cluster", set to "" if you do not want to provision an AKS cluster
    -var="AKS_NODE_COUNT=3"                       \  # optional, defaults to 3
    -var="AKS_NODE_VM_SIZE=Standard_D16s_v3"      \  # optional, defaults to Standard_D16s_v3. Use Standard_D4s_v3 for smaller workloads
    -var="SETUP_LOCAL_HOST=false"                 \  # optional, defaults to false, set to true if you don't want a bastion and you want to set up the local host with Juju and deploy the controller
    -var="CONTROLLER_CONSTRAINTS=cores=4 mem=8G"     # optional, defaults to "cores=4 mem=8G"

terraform apply terraform.out

popd
```

*Note* For sensitive variables like `azure_subscription_id`, it's generally better practice to pass them via environment variables (e.g., `TF_VAR_azure_subscription_id`) or a `terraform.tfvars` file to avoid exposing them directly on the command line in shell history.


#### b. Sourced as a module
To use this module, add a `module` block to your Terraform configuration:

```terraform
module "juju_azure_infra" {
  source = "git::https://github.com/canonical/charms-reference-architectures//clouds/azure?ref=main" # Adjust path if module is local or use registry source

  azure_subscription_id     = var.azure_subscription_id
  resource_group_name       = var.resource_group_name
  region                    = var.region
  provision_bastion         = var.provision_bastion
  ssh_public_key            = var.ssh_public_key
  ssh_private_key           = var.ssh_private_key
  source_address_prefixes   = var.source_address_prefixes
  aks_cluster_name          = var.aks_cluster_name
  setup_local_host          = var.setup_local_host
}
```

AKS limits the number of Azure Disks that can be attached to each node based on
the selected VM size. Storage-heavy deployments such as a MongoDB sharded
cluster should use a VM size with sufficient data-disk attachment capacity.
Increasing `AKS_NODE_COUNT` adds attachment capacity horizontally; increasing
`AKS_NODE_VM_SIZE` can increase the per-node attachment limit. Confirm the
effective limit after provisioning with `kubectl get csinode`.

## License

This module is licensed under the [Apache License](../../LICENSE).
