
data "terraform_remote_state" "infra_state" {
  backend = "azurerm"
  config = {
    resource_group_name  = "tfstate-rg"
    storage_account_name = "tfstate0fcsksld"
    container_name       = "tfstate"
    key                  = "infra.terraform.tfstate"
  }
}

resource "juju_model" "vm_model" {
  name = var.etcd.model
  cloud {
    name = "azure"
  }
  config = {
    "resource-group-name" = data.terraform_remote_state.infra_state.outputs.infrastructure.resource_group_name
    "network"             = data.terraform_remote_state.infra_state.outputs.infrastructure.vnet_name
  }
}

# workaround because you cannot create a k8s model with a service-principal-secret auth
resource "null_resource" "create_k8s_model" {

  triggers = {
    model-name = var.cos.model
  }

  provisioner "local-exec" {
    command = "juju add-model ${var.cos.model} k8s"
  }

  provisioner "local-exec" {
    when    = destroy
    command = "juju remove-model --destroy-storage --force --no-wait --no-prompt ${self.triggers.model-name}"
  }
}

module "cos" {
  source  = "git::https://github.com/canonical/observability-stack//terraform/cos-lite"
  model   = var.cos.model
  channel = var.cos.channel
  use_tls = var.cos.use_tls

  depends_on = [
    null_resource.create_k8s_model,
  ]
}


module "etcd" {
  source                   = "git::https://github.com/canonical/charmed-etcd-operator//terraform/product"
  etcd                     = var.etcd
  grafana-agent            = var.grafana-agent
  backups-integrator       = var.backups-integrator
  data-integrator          = var.data-integrator
  self-signed-certificates = var.self-signed-certificates

  depends_on = [
    juju_model.vm_model,
  ]
}


resource "juju_integration" "grafana-agent-prometheus" {
  model = var.etcd.model

  application {
    name     = module.etcd.app_names.grafana-agent
    endpoint = "send-remote-write"
  }
  application {
    offer_url = module.cos.offers.prometheus_receive_remote_write.url
  }
}

resource "juju_integration" "grafana-agent-loki" {
  model = var.etcd.model

  application {
    name     = module.etcd.app_names.grafana-agent
    endpoint = "logging-consumer"
  }
  application {
    offer_url = module.cos.offers.loki_logging.url
  }
}

resource "juju_integration" "grafana-agent-dashboards" {
  model = var.etcd.model

  application {
    name     = module.etcd.app_names.grafana-agent
    endpoint = "grafana-dashboards-provider"
  }
  application {
    offer_url = module.cos.offers.grafana_dashboards.url
  }
}
