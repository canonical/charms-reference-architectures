# Copyright 2025 Canonical Ltd.
# See LICENSE file for licensing details.

output "infrastructure" {
  value = {
    vpc_id                = aws_vpc.main_vpc.id
    controller_subnet_id  = aws_subnet.controller_subnet.id
    deployments_subnet_id = aws_subnet.deployments_subnet.id
    bastion_public_ip     = aws_instance.bastion_host.public_ip
  }
}