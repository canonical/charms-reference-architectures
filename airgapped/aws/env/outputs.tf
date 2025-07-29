# Copyright 2025 Canonical Ltd.
# See LICENSE file for licensing details.

## -------- VPC
output "vpc_id" {
  value = aws_vpc.vpc.id
  description = "The VPC in which the deployment is operating."
}

## -------- SUBNETS
output "subnet_vpn" {
  value = aws_subnet.subnet_vpn.id
  description = "The subnet in which the VPN instance is deployed."
}

output "subnet_bastion" {
  value = aws_subnet.subnet_bastion.id
  description = "The subnet in which the bastion is deployed."
}

output "subnet_snap_store_proxy" {
  value = aws_subnet.subnet_snap_store_proxy.id
  description = "The subnet in which the snap store is deployed."
}

output "subnet_juju_controller" {
  value = aws_subnet.subnet_juju_controller.id
  description = "The subnet in which the juju controller instance is deployed."
}

output "subnet_juju_apps" {
  value = aws_subnet.subnet_juju_apps.id
  description = "The subnet in which the charms are deployed."
}

## -------- AMIs
output "bastion_ami" {
  value = try(tolist(aws_imagebuilder_image.bastion_image.output_resources[0].amis)[0].image, "")
}

output "estore_ociregistry_ami" {
  value = try(tolist(aws_imagebuilder_image.estore_ociregistry_image.output_resources[0].amis)[0].image, "")
}

output "juju_controller_ami" {
  value = try(tolist(aws_imagebuilder_image.juju_controller_image.output_resources[0].amis)[0].image, "")
}

output "juju_machine_apps_ami" {
  value = try(tolist(aws_imagebuilder_image.juju_machine_apps_image.output_resources[0].amis)[0].image, "")
}

output "juju_k8s_apps_ami" {
  value = try(tolist(aws_imagebuilder_image.juju_k8s_apps_image.output_resources[0].amis)[0].image, "")
}
