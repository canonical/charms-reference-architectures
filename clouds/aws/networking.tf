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

# --- public subnets (host NAT gateways and bastion)

resource "aws_subnet" "public_a_subnet" {
  vpc_id                  = aws_vpc.main_vpc.id
  cidr_block              = "10.0.10.0/24"
  availability_zone       = "${var.REGION}a"
  map_public_ip_on_launch = true
}

resource "aws_subnet" "public_b_subnet" {
  vpc_id                  = aws_vpc.main_vpc.id
  cidr_block              = "10.0.11.0/24"
  availability_zone       = "${var.REGION}b"
  map_public_ip_on_launch = true
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
  cidr_block              = "10.0.3.0/24"
  availability_zone       = "${var.REGION}b"
  map_public_ip_on_launch = false
}



resource "aws_internet_gateway" "internet_gateway" {
  vpc_id = aws_vpc.main_vpc.id
}

# --- Connect controller_subnet to internet
# Routing table
resource "aws_route_table" "public_routing_table" {
  vpc_id = aws_vpc.main_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.internet_gateway.id
  }

  depends_on = [aws_internet_gateway.internet_gateway]
}

# Associate route to subnet
resource "aws_route_table_association" "public_a_subnet_assoc" {
  subnet_id      = aws_subnet.public_a_subnet.id
  route_table_id = aws_route_table.public_routing_table.id
}

resource "aws_route_table_association" "public_b_subnet_assoc" {
  subnet_id      = aws_subnet.public_b_subnet.id
  route_table_id = aws_route_table.public_routing_table.id
}

# --- Connect public_a_subnet to internet
# Public IP address
resource "aws_eip" "public_a_nat_gateway_pip" {
  domain     = "vpc"
  depends_on = [aws_internet_gateway.internet_gateway]
}

# --- Connect public_b_subnet to internet
# Public IP address
resource "aws_eip" "public_b_nat_gateway_pip" {
  domain     = "vpc"
  depends_on = [aws_internet_gateway.internet_gateway]
}

# NAT Gateway
resource "aws_nat_gateway" "public_a_nat_gateway" {
  allocation_id = aws_eip.public_a_nat_gateway_pip.id
  subnet_id     = aws_subnet.public_a_subnet.id
}

resource "aws_nat_gateway" "public_b_nat_gateway" {
  allocation_id = aws_eip.public_b_nat_gateway_pip.id
  subnet_id     = aws_subnet.public_b_subnet.id
}

# Private routing table
resource "aws_route_table" "private_a_routing_table" {
  vpc_id = aws_vpc.main_vpc.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.public_a_nat_gateway.id
  }

  depends_on = [aws_nat_gateway.public_a_nat_gateway]
}

resource "aws_route_table" "private_b_routing_table" {
  vpc_id = aws_vpc.main_vpc.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.public_b_nat_gateway.id
  }

  depends_on = [aws_nat_gateway.public_b_nat_gateway]
}

# Associate routing table to subnet
resource "aws_route_table_association" "controller_private_assoc" {
  subnet_id      = aws_subnet.controller_subnet.id
  route_table_id = aws_route_table.private_a_routing_table.id
}

resource "aws_route_table_association" "deployment_peers_private_assoc" {
  subnet_id      = aws_subnet.deployments_peers_subnet.id
  route_table_id = aws_route_table.private_b_routing_table.id
}

resource "aws_route_table_association" "deployment_clients_private_assoc" {
  subnet_id      = aws_subnet.deployments_clients_subnet.id
  route_table_id = aws_route_table.private_b_routing_table.id
}

