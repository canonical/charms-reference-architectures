# Copyright 2026 Canonical Ltd.
# See LICENSE file for licensing details.

resource "aws_security_group" "dashboards_frontend" {
  count       = local.lb_public ? 1 : 0
  name_prefix = "${var.opensearch_model}-dashboards-frontend-"
  description = "Allowed public OpenSearch Dashboards clients"
  vpc_id      = var.vpc_id
}

resource "aws_vpc_security_group_ingress_rule" "dashboards_clients" {
  for_each          = local.lb_public ? local.lb.allowed_cidrs : toset([])
  security_group_id = aws_security_group.dashboards_frontend[0].id
  cidr_ipv4         = each.value
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
}

resource "aws_vpc_security_group_egress_rule" "dashboards_backends" {
  count                        = local.lb_public ? 1 : 0
  security_group_id            = aws_security_group.dashboards_frontend[0].id
  referenced_security_group_id = aws_security_group.dashboards_backend[0].id
  ip_protocol                  = "tcp"
  from_port                    = 5601
  to_port                      = 5601
}

# Let the OpenSearch Dashboards machines accept traffic from the public NLB.
resource "aws_security_group" "dashboards_backend" {
  count       = local.lb_public ? 1 : 0
  name_prefix = "${var.opensearch_model}-dashboards-backend-"
  description = "OpenSearch Dashboards traffic from the public NLB"
  vpc_id      = var.vpc_id

  lifecycle {
    create_before_destroy = true
    replace_triggered_by  = [terraform_data.dashboards_backends[0]]
  }
}

resource "aws_vpc_security_group_ingress_rule" "dashboards_backends" {
  count                        = local.lb_public ? 1 : 0
  security_group_id            = aws_security_group.dashboards_backend[0].id
  referenced_security_group_id = aws_security_group.dashboards_frontend[0].id
  ip_protocol                  = "tcp"
  from_port                    = 5601
  to_port                      = 5601
}

data "aws_instance" "dashboards" {
  count       = local.lb_public ? local.lb_target_count : 0
  instance_id = data.juju_machine.dashboards[count.index].instance_id

  filter {
    name   = "vpc-id"
    values = [var.vpc_id]
  }
}

resource "aws_network_interface_sg_attachment" "dashboards" {
  count                = local.lb_public ? local.lb_target_count : 0
  security_group_id    = aws_security_group.dashboards_backend[0].id
  network_interface_id = data.aws_instance.dashboards[count.index].network_interface_id
}
