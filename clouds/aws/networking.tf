# Copyright 2025 Canonical Ltd.
# See LICENSE file for licensing details.

## ====================================================
## Network infra
## ====================================================

# --- networks
resource "aws_vpc" "main_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true
}

resource "aws_subnet" "controller_subnet" {
  vpc_id                  = aws_vpc.main_vpc.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "${var.REGION}a"
  map_public_ip_on_launch = false
}

resource "aws_subnet" "deployments_peers_subnet" {
  vpc_id                  = aws_vpc.main_vpc.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "${var.REGION}b"
  map_public_ip_on_launch = false
}

resource "aws_subnet" "deployments_clients_subnet" {
  vpc_id                  = aws_vpc.main_vpc.id
  cidr_block              = "10.0.4.0/24"
  availability_zone       = "${var.REGION}b"
  map_public_ip_on_launch = false
}

resource "aws_subnet" "bastion_subnet" {
  count                   = var.PROVISION_BASTION ? 1 : 0
  vpc_id                  = aws_vpc.main_vpc.id
  cidr_block              = "10.0.3.0/24"
  availability_zone       = "${var.REGION}a"
  map_public_ip_on_launch = true
}

# --- internet gateway
resource "aws_internet_gateway" "internet_gateway" {
  vpc_id = aws_vpc.main_vpc.id
}

# --- Connect controller/deployments subnets to internet
# Public IP address
resource "aws_eip" "controller_nat_gateway_pip" {
  domain     = "vpc"
  depends_on = [aws_internet_gateway.internet_gateway]
}

resource "aws_eip" "deployments_peer_nat_gateway_pip" {
  domain     = "vpc"
  depends_on = [aws_internet_gateway.internet_gateway]
}

resource "aws_eip" "deployments_clients_nat_gateway_pip" {
  domain     = "vpc"
  depends_on = [aws_internet_gateway.internet_gateway]
}

# NAT Gateway
resource "aws_nat_gateway" "controller_nat_gateway" {
  allocation_id = aws_eip.controller_nat_gateway_pip.id
  subnet_id     = aws_subnet.controller_subnet.id
}

resource "aws_nat_gateway" "deployments_peers_nat_gateway" {
  allocation_id = aws_eip.deployments_peer_nat_gateway_pip.id
  subnet_id     = aws_subnet.deployments_peers_subnet.id
}

resource "aws_nat_gateway" "deployments_clients_nat_gateway" {
  allocation_id = aws_eip.deployments_clients_nat_gateway_pip.id
  subnet_id     = aws_subnet.deployments_clients_subnet.id
}

# Routing tables
resource "aws_route_table" "controller_nat_routing_table" {
  vpc_id = aws_vpc.main_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_nat_gateway.controller_nat_gateway.id
  }

  depends_on = [aws_nat_gateway.controller_nat_gateway]
}

resource "aws_route_table" "deployments_peers_nat_routing_table" {
  vpc_id = aws_vpc.main_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_nat_gateway.deployments_peers_nat_gateway.id
  }

  depends_on = [aws_nat_gateway.deployments_peers_nat_gateway]
}

resource "aws_route_table" "deployments_clients_nat_routing_table" {
  vpc_id = aws_vpc.main_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_nat_gateway.deployments_clients_nat_gateway.id
  }

  depends_on = [aws_nat_gateway.deployments_clients_nat_gateway]
}

resource "aws_route_table" "bastion_routing_table" {
  count      = var.PROVISION_BASTION ? 1 : 0
  vpc_id     = aws_vpc.main_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.internet_gateway.id
  }

  depends_on = [aws_internet_gateway.internet_gateway]
}

# Associate route to subnets
resource "aws_route_table_association" "controller_nat_internet_connection" {
  subnet_id      = aws_subnet.controller_subnet.id
  route_table_id = aws_route_table.controller_nat_routing_table.id
}

resource "aws_route_table_association" "deployments_peers_nat_internet_connection" {
  subnet_id      = aws_subnet.deployments_peers_subnet.id
  route_table_id = aws_route_table.deployments_peers_nat_routing_table.id
}

resource "aws_route_table_association" "deployments_clients_nat_internet_connection" {
  subnet_id      = aws_subnet.deployments_clients_subnet.id
  route_table_id = aws_route_table.deployments_clients_nat_routing_table.id
}

resource "aws_route_table_association" "bastion_internet_connection" {
  count          = var.PROVISION_BASTION ? 1 : 0
  subnet_id      = aws_subnet.bastion_subnet[count.index].id
  route_table_id = aws_route_table.bastion_routing_table[count.index].id
}
