# Copyright 2025 Canonical Ltd.
# See LICENSE file for licensing details.


# Add A records to the private "canonical.internal" hosted zone
data "aws_route53_zone" "private_proxy_zone" {
  name         = "canonical.internal"
  private_zone = true

  vpc_id = data.terraform_remote_state.amis_networking.outputs.vpc_id
}

resource "aws_route53_record" "oci_registry_record" {
  zone_id = data.aws_route53_zone.private_proxy_zone.zone_id
  name    = "oci-registry.canonical.internal"
  type    = "A"
  ttl     = 60
  records = [aws_instance.estore_ociregistry_instance.private_ip]
}

resource "aws_route53_record" "snapstore_proxy_record" {
  zone_id = data.aws_route53_zone.private_proxy_zone.zone_id
  name    = "snapstore-proxy.canonical.internal"
  type    = "A"
  ttl     = 60
  records = [aws_instance.estore_ociregistry_instance.private_ip]
}

# Interface VPC endpoints (private link)
# for ec2
resource "aws_vpc_endpoint" "ec2_vpc_endpoint" {
  vpc_id            = data.terraform_remote_state.amis_networking.outputs.vpc_id
  service_name      = "com.amazonaws.${var.region}.ec2"
  vpc_endpoint_type = "Interface"
  private_dns_enabled = true
  subnet_ids        = [
    data.terraform_remote_state.amis_networking.outputs.subnet_bastion,
    data.terraform_remote_state.amis_networking.outputs.subnet_juju_controller,
    data.terraform_remote_state.amis_networking.outputs.subnet_juju_apps
  ]
  security_group_ids = [aws_security_group.vpc_endpoint_sg.id]
}

resource "aws_vpc_endpoint" "sts_vpc_endpoint" {
  vpc_id            = data.terraform_remote_state.amis_networking.outputs.vpc_id
  service_name      = "com.amazonaws.${var.region}.sts"
  vpc_endpoint_type = "Interface"
  private_dns_enabled = true
  subnet_ids        = [
    data.terraform_remote_state.amis_networking.outputs.subnet_bastion,
    data.terraform_remote_state.amis_networking.outputs.subnet_juju_controller,
    data.terraform_remote_state.amis_networking.outputs.subnet_juju_apps
  ]
  security_group_ids = [aws_security_group.vpc_endpoint_sg.id]
}

resource "aws_vpc_endpoint" "iam_vpc_endpoint" {
  vpc_id            = data.terraform_remote_state.amis_networking.outputs.vpc_id
  service_name      = "com.amazonaws.iam"
  vpc_endpoint_type = "Interface"
  private_dns_enabled = true
  subnet_ids        = [
    data.terraform_remote_state.amis_networking.outputs.subnet_bastion,
    data.terraform_remote_state.amis_networking.outputs.subnet_juju_controller,
    data.terraform_remote_state.amis_networking.outputs.subnet_juju_apps
  ]
  security_group_ids = [aws_security_group.vpc_endpoint_sg.id]
}

# for s3
data "aws_route_table" "main" {
  filter {
    name   = "vpc-id"
    values = [data.terraform_remote_state.amis_networking.outputs.vpc_id]
  }

  filter {
    name   = "association.main"
    values = ["true"]
  }
}

resource "aws_vpc_endpoint" "s3" {
  vpc_id       = data.terraform_remote_state.amis_networking.outputs.vpc_id
  service_name = "com.amazonaws.${var.region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [data.aws_route_table.main.id]
}