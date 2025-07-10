# Copyright 2024 Canonical Ltd.
# See LICENSE file for licensing details.

output "public_ip_vpn" {
  value = aws_instance.vpn_instance.public_ip
  description = "The subnet in which the bastion is deployed."
}

output "private_ip_bastion" {
  value = aws_instance.bastion_instance.private_ip
  description = "The subnet in which the bastion is deployed."
}
