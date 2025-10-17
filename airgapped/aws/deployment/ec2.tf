# Copyright 2025 Canonical Ltd.
# See LICENSE file for licensing details.


resource "aws_key_pair" "internal_key_pair" {
  key_name = "internal"
  public_key = file("${path.module}/keys/internal.pub")
}

data "local_file" "internal_private_key" {
  filename = "${path.module}/keys/internal"
}

data "aws_ami" "ubuntu_22" {
  most_recent = true
  owners = ["099720109477"] # Canonical

  filter {
    name = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_instance" "vpn_instance" {
  ami                         = data.aws_ami.ubuntu_22.id
  instance_type               = "t2.medium" # api error Unsupported: Your requested instance type (t3.micro) is not supported in your requested Availability Zone
  subnet_id                   = data.terraform_remote_state.amis_networking.outputs.subnet_vpn
  associate_public_ip_address = true
  key_name                    = "admin"
  vpc_security_group_ids      = [aws_security_group.vpn_sg.id]
  user_data = templatefile("${path.module}/scripts/cloudinit-vpn.tftpl", {
    vpn_client_public_key = var.vpn_client_public_key
  })

  tags = {
    Name = "vpn"
  }
}

resource "aws_instance" "k8s_juju_apps_instance" {
  ami                         = data.terraform_remote_state.amis_networking.outputs.juju_k8s_apps_ami
  instance_type               = "t3.large"
  subnet_id                   = data.terraform_remote_state.amis_networking.outputs.subnet_juju_apps
  associate_public_ip_address = false
  vpc_security_group_ids      = [aws_security_group.juju_apps_sg.id]
  key_name                    = aws_key_pair.internal_key_pair.id
  iam_instance_profile        = aws_iam_instance_profile.juju_unit_instance_profile.name

  user_data = templatefile("${path.module}/scripts/cloudinit-juju-k8s-host.tftpl", {
    internal_private_key = data.local_file.internal_private_key.content
  })

  tags = {
    Name = "microk8s"
  }
}

resource "aws_instance" "bastion_instance" {
  ami                         = data.terraform_remote_state.amis_networking.outputs.bastion_ami
  instance_type               = "t3.medium"
  subnet_id                   = data.terraform_remote_state.amis_networking.outputs.subnet_bastion
  associate_public_ip_address = false
  key_name                    = "admin"
  vpc_security_group_ids      = [aws_security_group.bastion_sg.id]
  iam_instance_profile        = aws_iam_instance_profile.bastion_instance_profile.name

  user_data = templatefile("${path.module}/scripts/cloudinit-bastion.tftpl", {
    internal_private_key      = data.local_file.internal_private_key.content
    region                    = var.region
    juju_version              = "3.6.5"
    architecture              = "amd64"
    vpc_id                    = data.terraform_remote_state.amis_networking.outputs.vpc_id
    juju_controller_ami_id    = data.terraform_remote_state.amis_networking.outputs.juju_controller_ami
    juju_controller_subnet_id = data.terraform_remote_state.amis_networking.outputs.subnet_juju_controller
    juju_unit_ami_id          = data.terraform_remote_state.amis_networking.outputs.juju_machine_apps_ami
    juju_unit_subnet_id       = data.terraform_remote_state.amis_networking.outputs.subnet_juju_apps
    store_inst_ip             = aws_instance.estore_ociregistry_instance.private_ip
    k8s_inst_ip               = aws_instance.k8s_juju_apps_instance.private_ip

  })

  tags = {
    Name = "bastion"
  }

  depends_on = [
    aws_instance.estore_ociregistry_instance,
    aws_instance.k8s_juju_apps_instance
  ]
}

resource "aws_instance" "estore_ociregistry_instance" {
  ami                         = data.terraform_remote_state.amis_networking.outputs.estore_ociregistry_ami
  instance_type               = "t2.medium"
  subnet_id                   = data.terraform_remote_state.amis_networking.outputs.subnet_snap_store_proxy
  associate_public_ip_address = false
  key_name                    = aws_key_pair.internal_key_pair.key_name
  vpc_security_group_ids      = [aws_security_group.store_registry_sg.id]

  tags = {
    Name = "store"
  }
}

