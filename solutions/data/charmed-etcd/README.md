# Charmed etcd solution
This is a Terraform module facilitating the deployment of the etcd charm with [Terraform juju provider](https://github.com/juju/terraform-provider-juju/) in a production setting. For more information, refer to the provider [documentation](https://registry.terraform.io/providers/juju/juju/latest/docs). 

## Requirements
This module requires the following:
- Terraform to be installed on the host machine.
- Juju to be installed on the host machine.
- A Juju controller already set up and accessible from the host machine including both VM and k8s clouds.

## Inputs
The module offers the following configurable inputs:
| Name                       | Type                                                                                                                                                                    | Description                                             | Required |
| -------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------- | -------- |
| `cos`                      | Includes the model name, charm channel, and whether or not to use TLS for cos.                                                                                          | Configuration for the Charmed Observability Stack (COS) | False    |
| `etcd`                     | object <br/>(structure as defined in etcd input variables)                                                                                                              | `etcd` application                                      | **True** |
| `backups-integrator`       | object <br/>(structure as defined in the `azure-storage-integrator`/`s3-integrator` charms, with the addition of an attribute: <br/>- `storage_type` = "s3" or "azure") | Backup (s3/azure) integrator application                | False    |
| `data-integrator`          | object <br/>(structure as defined in the `data-integrator` charm)                                                                                                       | `data-integrator` application                           | False    |
| `self-signed-certificates` | object <br/>(structure as defined in the self-signed-certificates charm)                                                                                                | `self-signed-certificates` application                  | False    |
| `grafana-agent`            | object <br/>(structure as defined in the grafana-agent charm)                                                                                                           | `grafana-agent` application                             | False    |

## Usage
To use this module, run the following command in your terminal:

```bash
terraform init
terraform apply -var 'cos={"model": "k8s", "channel": "2/edge", "use_tls": false}' -var 'etcd={"model": "vm"}' -var 'backups-integrator={"config": {"bucket": "test"}}'
```