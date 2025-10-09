# Copyright 2025 Canonical Ltd.
# See LICENSE file for licensing details.

## ====================================================
## Provision and set up Bastion Host for juju (Optional)
## ====================================================

# security group for bastion access
resource "aws_security_group" "bastion_sg" {
  vpc_id      = aws_vpc.main_vpc.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.SOURCE_ADDRESSES
    description = "SSH access from allowed IPs"
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

# Security group for access from bastion to controller subnet
resource "aws_security_group" "bastion_to_controller_sg" {
  vpc_id      = aws_vpc.main_vpc.id

  ingress {
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion_sg.id]
    description     = "SSH access from bastion host"
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


resource "aws_iam_role" "bastion_role" {
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "bastion_role_attachment" {
  role       = aws_iam_role.bastion_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "bastion_profile" {
  role    = aws_iam_role.bastion_role.name
}

resource "aws_instance" "bastion_host" {
  ami                    = "ami-0a116fa7c861dd5f9" #Ubuntu 24.04
  instance_type          = "t2.medium"
  key_name               = var.SSH_KEY
  subnet_id              = aws_subnet.bastion_subnet.id
  vpc_security_group_ids = [aws_security_group.bastion_sg.id]
  iam_instance_profile   = aws_iam_instance_profile.bastion_profile.name

  root_block_device {
    volume_type           = "gp2"
    volume_size           = 20
    delete_on_termination = true
    encrypted             = true
  }

  depends_on = [aws_subnet.controller_subnet, aws_iam_instance_profile.bastion_profile]
}

resource "null_resource" "set_up_bastion_script" {
  provisioner "file" {
    content = templatefile("scripts/setup-juju-env.tftpl", {
      region                 = var.REGION,
      vpc_id                 = aws_vpc.main_vpc.id,
      subnet_id              = aws_subnet.bastion_subnet.id, # revert
      access_key             = var.ACCESS_KEY,
      secret_key             = var.SECRET_KEY,
    })
    destination = "setup-juju-env.sh"
  }

  provisioner "remote-exec" {
    inline = [
      "bash ~/setup-juju-env.sh",
      "rm ~/setup-juju-env.sh",
    ]
  }

  connection {
    type        = "ssh"
    host        = aws_instance.bastion_host.public_ip
    user        = "ubuntu"
    private_key = file(var.SSH_KEY_FILE)
  }

  depends_on = [aws_instance.bastion_host]
}
