# Copyright 2025 Canonical Ltd.
# See LICENSE file for licensing details.

resource "aws_security_group" "vpn_sg" {
  name        = "wireguard-vpn-sg"
  description = "Allow VPN traffic"
  vpc_id      = data.terraform_remote_state.amis_networking.outputs.vpc_id

  ingress {
    description = "WireGuard UDP"
    from_port   = 51820
    to_port     = 51820
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "SSH from WireGuard clients"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "bastion_sg" {
  name   = "bastion-sg"
  vpc_id = data.terraform_remote_state.amis_networking.outputs.vpc_id

  ingress {
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.vpn_sg.id]
    description     = "SSH from WireGuard clients"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "juju_controller_sg" {
  name        = "juju-controller-sg"
  description = "Juju controller SG"
  vpc_id      = data.terraform_remote_state.amis_networking.outputs.vpc_id

  # SSH from Bastion
  ingress {
    description     = "SSH from Bastion"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion_sg.id]
  }

  # Juju agents from apps
  ingress {
    description     = "Juju agent traffic from Juju apps"
    from_port       = 17070
    to_port         = 17099
    protocol        = "tcp"
    cidr_blocks     = ["10.0.3.0/24"]
  }

  # Outbound all
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "juju-controller-sg"
  }
}

resource "aws_security_group" "juju_apps_sg" {
  name        = "juju-apps-sg"
  description = "Juju apps SG"
  vpc_id      = data.terraform_remote_state.amis_networking.outputs.vpc_id

  # Full access from Bastion (test/debug anything)
  ingress {
    description     = "All access from Bastion for testing"
    from_port       = 0
    to_port         = 65535
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion_sg.id]
  }

  # Juju agent traffic from Controller
  ingress {
    description     = "Juju agent from Controller"
    from_port       = 17070
    to_port         = 17099
    protocol        = "tcp"
    security_groups = [aws_security_group.juju_controller_sg.id]
  }

  # microk8s api access from controller
  ingress {
    description     = "Allow MicroK8s API access from controller"
    from_port       = 16443
    to_port         = 16443
    protocol        = "tcp"
    security_groups = [aws_security_group.juju_controller_sg.id]
  }

  # Snap Store Proxy / OCI Registry (if applicable)
  ingress {
    description     = "Traffic from Snap Store Proxy / OCI Registry"
    from_port       = 0
    to_port         = 65535
    protocol        = "tcp"
    security_groups = [aws_security_group.store_registry_sg.id]
  }

  # Outbound traffic allowed
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "juju-apps-sg"
  }
}

resource "aws_security_group" "store_registry_sg" {
  name        = "store-registry-sg"
  description = "Access for snapstore proxy + oci registry"
  vpc_id      = data.terraform_remote_state.amis_networking.outputs.vpc_id

  # SSH access from Bastion
  ingress {
    description     = "SSH from Bastion"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion_sg.id]
  }

  # Snap Store Proxy (HTTP)
  ingress {
    description     = "HTTP for Snap Store Proxy"
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion_sg.id]
    cidr_blocks     = ["10.0.2.0/24", "10.0.3.0/24"]
  }

  # OCI Registry (port 5000)
  ingress {
    description     = "OCI Registry API"
    from_port       = 6000
    to_port         = 6000
    protocol        = "tcp"
    security_groups = [
      aws_security_group.bastion_sg.id,
      aws_security_group.juju_controller_sg.id,
    ]
    cidr_blocks     = ["10.0.3.0/24"]
  }

  # Outbound to internet (optional if needed)
  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "store-registry-sg"
  }
}

# VPC private endpoint
resource "aws_security_group" "vpc_endpoint_sg" {
  name   = "vpc-endpoint-sg"
  vpc_id = data.terraform_remote_state.amis_networking.outputs.vpc_id

  ingress {
    description     = "Allow HTTPS from EC2 components"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    cidr_blocks     = ["10.0.0.0/16"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
