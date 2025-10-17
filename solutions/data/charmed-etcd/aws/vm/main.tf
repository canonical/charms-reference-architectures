# Copyright 2025 Canonical Ltd.
# See LICENSE file for licensing details.

# requires the juju credentials to be provided as env variables
provider "juju" {}

resource "juju_model" "vm_model" {
  name = var.etcd.model
  cloud {
    name = "aws"
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
  source  = "git::https://github.com/canonical/observability-stack//terraform/cos-lite?ref=2.0a1"
  model   = var.cos.model
  channel = var.cos.channel

  depends_on = [
    juju_model.k8s_model,
  ]
}


module "etcd" {
  source                   = "git::https://github.com/canonical/charmed-etcd-operator//terraform/product?ref=3.6/edge"
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
