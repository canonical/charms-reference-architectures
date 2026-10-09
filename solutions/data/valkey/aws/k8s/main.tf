# Copyright 2026 Canonical Ltd.
# See LICENSE file for licensing details.

locals {
  # Without an explicit credential, Juju can pair the cloud with another cloud's credential.
  k8s_credential = var.k8s_credential != null ? var.k8s_credential : var.k8s_cloud
}

data "aws_region" "current" {}

module "cos" {
  source = "git::https://github.com/canonical/observability-stack//terraform/cos-lite?ref=tf-cos-lite-3.1.0"

  risk = var.risk

  model = {
    name       = var.cos_model
    cloud      = var.k8s_cloud == null ? null : { name = var.k8s_cloud }
    credential = local.k8s_credential
  }
}

module "valkey" {
  source = "git::https://github.com/canonical/valkey-operator//terraform/product/k8s?ref=9/edge"

  risk = var.risk

  model = {
    name       = var.valkey_model
    cloud      = var.k8s_cloud == null ? null : { name = var.k8s_cloud }
    credential = local.k8s_credential
  }

  # The server certificate must cover the load balancer IPs that external clients dial.
  valkey = {
    config = var.load_balancer == null ? {} : {
      certificate-extra-sans = join(",", aws_eip.valkey[*].public_ip)
    }
  }

  # The collector forwards metrics, logs and dashboards to COS Lite over cross-model relations.
  cos = {
    deploy     = {}
    prometheus = { kind = "offer", url = module.cos.offers.prometheus_receive_remote_write.url }
    loki       = { kind = "offer", url = module.cos.offers.loki_logging.url }
    grafana    = { kind = "offer", url = module.cos.offers.grafana_dashboards.url }
  }

  backup = {
    deploy = {
      storage_type = "s3"
      config = {
        bucket   = aws_s3_bucket.backups.id
        path     = var.s3_path
        region   = data.aws_region.current.region
        endpoint = "https://s3.${data.aws_region.current.region}.amazonaws.com"
      }
    }
  }
  s3_access_key     = aws_iam_access_key.valkey_backup.id
  s3_secret_key     = aws_iam_access_key.valkey_backup.secret
  s3_secret_version = var.s3_key_version

  # Referencing module.ssc orders the integration after the application exists. The product
  # module has its own provider block, so it cannot take depends_on.
  tls = {
    client_certificates = {
      kind     = "endpoint"
      name     = module.ssc.app_name
      endpoint = module.ssc.provides.certificates
    }
  }
}

module "ssc" {
  source = "git::https://github.com/canonical/self-signed-certificates-operator//terraform?ref=baf7355a536d454871b96e7afafcd166bbc029f2"

  channel     = "1/${var.risk}"
  constraints = null
  model_uuid  = module.valkey.models[var.valkey_model].model_uuid
}
