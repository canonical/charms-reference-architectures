# Copyright 2025 Canonical Ltd.
# See LICENSE file for licensing details.

# -------------------------------------------------------------------------
# VPC for test Region
resource "aws_vpc" "vpc" {
  cidr_block = "10.0.0.0/16"
  enable_dns_support = true      # provides an internal domain name
  enable_dns_hostnames = true      # provides an internal host name
  tags = {
    Name = "vpc-${var.region}-${var.team}"
  }
}

# -------------------------------------------------------------------------
# Internet Gateway
resource "aws_internet_gateway" "internet_gateway" {
  vpc_id = aws_vpc.vpc.id

  tags = {
    Name = "igw-${var.region}-${var.team}"
  }
}

# Route Table
resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.internet_gateway.id
  }

  tags = {
    Name = "public-route-table-${var.region}-${var.team}"
  }
}


# -------------------------------------------------------------------------
# Subnets in the VPC
resource "aws_subnet" "subnet_bastion" {
  vpc_id                  = aws_vpc.vpc.id
  cidr_block              = "10.0.0.0/24"
  availability_zone       = "${var.region}a"
  map_public_ip_on_launch = false
  tags = {
    Name = "subnet-bastion-${var.region}-${var.team}"
  }
}

resource "aws_subnet" "subnet_snap_store_proxy" {
  vpc_id                  = aws_vpc.vpc.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = false
  tags = {
    Name = "subnet-snap_store_proxy-${var.region}-${var.team}"
  }
}

resource "aws_subnet" "subnet_juju_controller" {
  vpc_id                  = aws_vpc.vpc.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "${var.region}b"
  map_public_ip_on_launch = false
  tags = {
    Name = "subnet-juju_controller-${var.region}-${var.team}"
  }
}

resource "aws_subnet" "subnet_juju_apps" {
  vpc_id                  = aws_vpc.vpc.id
  cidr_block              = "10.0.3.0/24"
  availability_zone       = "${var.region}c"
  map_public_ip_on_launch = false
  tags = {
    Name = "subnet-juju_apps-${var.region}-${var.team}"
  }
}

resource "aws_subnet" "subnet_vpn" {
  vpc_id                  = aws_vpc.vpc.id
  cidr_block              = "10.0.4.0/24"
  map_public_ip_on_launch = true

  tags = {
    Name = "subnet-public-vpn-${var.region}-${var.team}"
  }
}

# Associate route table with subnet
resource "aws_route_table_association" "public_assoc" {
  subnet_id      = aws_subnet.subnet_vpn.id
  route_table_id = aws_route_table.public_rt.id
}

# -------------------------------------------------------------------------
# Private Hosted Zone
resource "aws_route53_zone" "hosted_zone_private" {
  name = "canonical.internal"
  vpc {
    vpc_id = aws_vpc.vpc.id
  }
  comment = "Private DNS for airgapped internal resolution."
  tags = {
    Name = "route53-zone-${var.region}-${var.team}"
  }
}
