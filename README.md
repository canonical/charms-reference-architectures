# charms-reference-architectures
Repo for clouds &amp; substrates Terraform reference architectures of charms

## Clouds
The `clouds` directory contains Terraform modules designed to provision the necessary infrastructure for running Juju applications in various cloud environment.

The cloud provisioning modules are located in the `clouds` directory, with subdirectories for each cloud provider. Each subdirectory contains a `README.md` file that provides detailed instructions on how to use the module, including input variables, outputs, and usage examples.

Example: [`clouds/azure`](clouds/azure/README.md)

## Solutions
The `solutions` directory contains Terraform modules for deploying specific solutions or applications using Juju. These modules are designed to work with the cloud provisioning modules to create a complete solution stack.

The solution modules are categorized by team, product, cloud, and substrate. Each module has its own `README.md` file that provides detailed instructions on how to use the module, including input variables, outputs, and usage examples.

Example: [`solutions/data/charmed-etcd/azure/vm`](solutions/data/charmed-etcd/azure/vm/README.md)

## Air gapped testing
The `airgapped` directory contains Terraform modules for creating a fully air-gapped environment for development or testing. 
Then deploying VM & K8s charms as well as snaps in a fully cloud-based air-gapped environment.  

Example: [`airgapped/aws`](airgapped/aws/README.md)
