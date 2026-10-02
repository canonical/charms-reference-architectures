# Copyright 2025 Canonical Ltd.
# See LICENSE file for licensing details.

## ===============================================
## Set up localhost for Juju Controller (Optional)
## ===============================================


resource "local_file" "host_set_up_script" {
  count    = var.SETUP_LOCAL_HOST ? 1 : 0
  filename = "${path.module}/scripts/setup-juju-env.sh"
  # Holds the AWS keys
  file_permission = "0700"
  # The controller goes in the public subnet so the local client can reach it
  content = templatefile("scripts/setup-juju-env.tftpl", {
    bastion          = false,
    region           = var.REGION,
    vpc_id           = aws_vpc.main_vpc.id,
    subnet_id        = aws_subnet.public_a_subnet.id,
    access_key       = var.ACCESS_KEY,
    secret_key       = var.SECRET_KEY,
    eks_cluster_name = var.EKS_CLUSTER_NAME
  })
  depends_on = [
    aws_vpc.main_vpc,
    aws_route_table_association.public_a_subnet_assoc,
    aws_eks_cluster.eks,
  ]
}

# Execute the script on the local host
resource "null_resource" "SETUP_LOCAL_HOST" {
  count = var.SETUP_LOCAL_HOST ? 1 : 0

  provisioner "local-exec" {
    command = "bash ${local_file.host_set_up_script[0].filename}"
  }
}
