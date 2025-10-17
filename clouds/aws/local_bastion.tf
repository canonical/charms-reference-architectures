# Copyright 2025 Canonical Ltd.
# See LICENSE file for licensing details.

## ===============================================
## Set up localhost for Juju Controller (Optional)
## ===============================================


resource "local_file" "host_set_up_script" {
  count           = var.SETUP_LOCAL_HOST ? 1 : 0
  filename        = "${path.module}/scripts/setup-juju-env.sh"
  content         = templatefile("scripts/setup-juju-env.tftpl", {
    region        = var.REGION,
    vpc_id        = aws_vpc.main_vpc.id,
    subnet_id     = aws_subnet.controller_subnet.id,
    access_key    = var.ACCESS_KEY,
    secret_key    = var.SECRET_KEY,
  })
  depends_on = [aws_vpc.main_vpc, aws_subnet.controller_subnet]
}

# Execute the script on the local host
resource "null_resource" "SETUP_LOCAL_HOST" {
  count = var.SETUP_LOCAL_HOST ? 1 : 0

  provisioner "local-exec" {
    command = "bash ${local_file.host_set_up_script[0].filename}"
  }
}