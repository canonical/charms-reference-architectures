# Copyright 2025 Canonical Ltd.
# See LICENSE file for licensing details.

## ====================================================
## Network Security Group for SSH Access
## ====================================================

resource "aws_security_group" "main_nsg" {
  vpc_id   = aws_vpc.main_vpc.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.SOURCE_ADDRESSES
    description = "SSH access from allowed IPs"
  }

  ingress {
    from_port   = 17070
    to_port     = 17070
    protocol    = "tcp"
    cidr_blocks = var.SOURCE_ADDRESSES
    description = "Juju from allowed IPs"
  }

  ingress {
    from_port   = -1
    to_port     = -1
    protocol    = "icmp"
    cidr_blocks = var.SOURCE_ADDRESSES
    description = "ICMP from allowed IPs"
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = var.SOURCE_ADDRESSES
    description = "HTTP from allowed IPs"
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = var.SOURCE_ADDRESSES
    description = "HTTPS from allowed IPs"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }

  depends_on = [aws_vpc.main_vpc]
}