# Charmed etcd Solution Terraform Module

This Terraform module facilitates the deployment of the [etcd charm](https://charmhub.io/etcd) using the [Terraform Juju provider](https://github.com/juju/terraform-provider-juju/). It is designed for production-grade deployments, enabling robust and scalable etcd clusters with optional integrations for observability, backup, and data integration. For detailed information on the Juju provider, refer to its [documentation](https://registry.terraform.io/providers/juju/juju/latest/docs).

## Features

  * **Production-Ready etcd Deployment**: Facilitates the deployment of a highly available etcd cluster using best practices.
  * **Observability Integration**: Seamlessly integrates with the Canonical Observability Stack (COS) for monitoring and logging (COS lite).
  * **Backup and Restore**: Configures backup solutions (Azure Blob Storage or S3) via the `backups-integrator` charm.
  * **Data Integration**: Provides an option to integrate with the `data-integrator` charm for broader data integration scenarios.
  * **TLS Security**: Supports TLS for secure communication within the etcd cluster and with integrated services.
  * **Self-Signed Certificates**: Integration with the `self-signed-certificates` charm for simplified certificate management.

## Requirements

Before using this module, ensure you have the following prerequisites in place on your host machine:

  * **Terraform**: Version `1.0.0` or higher.
  * **Juju**: Version `3.6` or higher.
  * **Juju Controller**: A Juju controller must be already set up and accessible from your host machine. This includes:
      * A Juju controller with both VM-based clouds (e.g., AWS, Azure, GCP) and Kubernetes-based clouds (e.g., MicroK8s, Charmed Kubernetes) configured. 

## Module Inputs

The module exposes the following configurable input variables. Each variable corresponds to a Juju application and its associated configuration.

| Name                       | Type                                                                                                                                                                      | Description                                                                                                                                                                                                                                                           | Required | Default                                          |
| :------------------------- | :------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | :-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | :------- | :----------------------------------------------- |
| `cos`                      | `object({ model: string, channel: string, use_tls: bool })`                                                                                                               | Configuration for the Charmed Observability Stack (COS). <br> - `model`: The Juju model name where COS will be deployed (e.g., "k8s"). <br> - `channel`: The charm channel (e.g., "stable", "2/edge"). <br> - `use_tls`: Whether to enable TLS for COS communication. | No       | `{model="k8s", channel="2/edge", use_tls=false}` |
| `etcd`                     | `object` (structure as defined in the [`charmed-etcd` charm](https://github.com/canonical/charmed-etcd-operator/blob/3.6/edge/terraform/product/variables.tf))            | Configuration for the `etcd` application deployment. This is the core of the module.                                                                                                                                                                                  | **Yes**  | `n/a`                                            |
| `backups_integrator`       | `object` (structure as defined in the [`charmed-etcd` charm](https://github.com/canonical/charmed-etcd-operator/blob/3.6/edge/terraform/product/variables.tf))structure . | Configuration for the backup integrator application.                                                                                                                                                                                                                  | **Yes**  | `null`                                           |
| `data_integrator`          | `object` (structure as defined in the [`charmed-etcd` charm](https://github.com/canonical/charmed-etcd-operator/blob/3.6/edge/terraform/product/variables.tf))            | Configuration for the `data-integrator` application.                                                                                                                                                                                                                  | No       | `{}`                                             |
| `self_signed_certificates` | `object` (structure as defined in the [`charmed-etcd` charm](https://github.com/canonical/charmed-etcd-operator/blob/3.6/edge/terraform/product/variables.tf))            | Configuration for the `self-signed-certificates` application.                                                                                                                                                                                                         | No       | `{}`                                             |
| `grafana_agent`            | `object` (structure as defined in the [`charmed-etcd` charm](https://github.com/canonical/charmed-etcd-operator/blob/3.6/edge/terraform/product/variables.tf))            | Configuration for the `grafana-agent` application.                                                                                                                                                                                                                    | No       | `{channel = "1/stable"}`                         |


## Usage

To utilize this module, include it in your Terraform configuration and provide the necessary input variables.


### Deployment Steps

Once your Terraform configuration is set up, execute the following commands in your terminal:

1.  **Initialize Terraform**: This command downloads the necessary providers and modules.

    ```bash
    terraform init
    ```

2. **Configure Juju controller**: Provide the required information for the Juju Terraform provider as environment variables.

    ```bash
    export JUJU_CONTROLLER_ADDRESSES="<controller addresses>"
    export JUJU_USERNAME="<username>"
    export JUJU_PASSWORD="<password>"
    ```

3. **Plan the Deployment**: Review the changes Terraform will apply. This is a crucial step to understand the impact of your configuration.

    ```bash
    terraform plan -out terraform.out \
      -var='etcd={}'                  \
      -var='backups-integrator={"storage_type": "s3", "config": {"access-key": "<my-access-key>", "secret-key": "<my-secret-key>"}}' \
      -var='remote-state={"bucket": "<myBucketName>", "region": "eu-central-1"}'  # TODO change this to the name of the bucket you've been using to store the state
    ```

3.  **Apply the Configuration**: This command executes the planned actions and deploys the charmed etcd solution.

    ```bash
    terraform apply
    ```

    You will be prompted to confirm the deployment. Type `yes` to proceed.

## License

This module is licensed under the [Apache License](../../../LICENSE).
