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
resource "aws_subnet" "public_a" {
  vpc_id                  = aws_vpc.main_vpc.id
  cidr_block              = "10.0.10.0/24"
  availability_zone       = "${var.REGION}a"
  map_public_ip_on_launch = true
}

resource "aws_subnet" "public_b" {
  vpc_id                  = aws_vpc.main_vpc.id
  cidr_block              = "10.0.11.0/24"
  availability_zone       = "${var.REGION}b"
  map_public_ip_on_launch = true
}

# --- private subnets (instances live here; outbound only via NAT)
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

# --- internet gateway
resource "aws_internet_gateway" "internet_gateway" {
  vpc_id = aws_vpc.main_vpc.id
}

# --- public route table (public subnets -> IGW)
resource "aws_route_table" "public_routing_table" {
  vpc_id = aws_vpc.main_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.internet_gateway.id
  }
}

resource "aws_route_table_association" "public_a_assoc" {
  subnet_id      = aws_subnet.public_a.id
  route_table_id = aws_route_table.public_routing_table.id
}

resource "aws_route_table_association" "public_b_assoc" {
  subnet_id      = aws_subnet.public_b.id
  route_table_id = aws_route_table.public_routing_table.id
}

# --- NAT gateways (one per AZ, in public subnets)
resource "aws_eip" "nat_a_eip" {
  domain     = "vpc"
  depends_on = [aws_internet_gateway.internet_gateway]
}

resource "aws_eip" "nat_b_eip" {
  domain     = "vpc"
  depends_on = [aws_internet_gateway.internet_gateway]
}

resource "aws_nat_gateway" "nat_a" {
  allocation_id = aws_eip.nat_a_eip.id
  subnet_id     = aws_subnet.public_a.id
  depends_on    = [aws_route_table_association.public_a_assoc]
}

resource "aws_nat_gateway" "nat_b" {
  allocation_id = aws_eip.nat_b_eip.id
  subnet_id     = aws_subnet.public_b.id
  depends_on    = [aws_route_table_association.public_b_assoc]
}

# --- private route tables (private subnets -> NAT in same AZ)
resource "aws_route_table" "private_a_routing_table" {
  vpc_id = aws_vpc.main_vpc.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat_a.id
  }
}

resource "aws_route_table" "private_b_routing_table" {
  vpc_id = aws_vpc.main_vpc.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat_b.id
  }
}

# --- associate private subnets to the correct private route table
resource "aws_route_table_association" "controller_private_assoc" {
  subnet_id      = aws_subnet.controller_subnet.id
  route_table_id = aws_route_table.private_a_routing_table.id
}

resource "aws_route_table_association" "deployments_peers_private_assoc" {
  subnet_id      = aws_subnet.deployments_peers_subnet.id
  route_table_id = aws_route_table.private_b_routing_table.id
}

resource "aws_route_table_association" "deployments_clients_private_assoc" {
  subnet_id      = aws_subnet.deployments_clients_subnet.id
  route_table_id = aws_route_table.private_b_routing_table.id
}
