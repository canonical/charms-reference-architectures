# Copyright 2025 Canonical Ltd.
# See LICENSE file for licensing details.

data "terraform_remote_state" "infra_state" {
  backend = "azurerm"
  config  = var.remote-state
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

resource "juju_model" "k8s_model" {
  name       = var.cos.model
  credential = "k8s"
  cloud {
    name = "k8s"
  }
}

module "cos" {
  source  = "git::https://github.com/canonical/observability-stack//terraform/cos-lite"
  model   = var.cos.model
  channel = var.cos.channel
  use_tls = var.cos.use_tls

  depends_on = [
    juju_model.k8s_model,
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
