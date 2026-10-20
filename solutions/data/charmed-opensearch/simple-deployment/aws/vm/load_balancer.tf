# Copyright 2026 Canonical Ltd.
# See LICENSE file for licensing details.

data "juju_machine" "dashboards" {
  count                 = local.lb_target_count
  model_uuid            = juju_model.opensearch.uuid
  machine_id            = sort(tolist(local.dashboards_app.machines))[count.index]
  wait_for_ip_addresses = ["private"]

  lifecycle {
    precondition {
      condition     = length(local.dashboards_app.machines) == var.opensearch_dashboards.units
      error_message = "OpenSearch Dashboards does not have the requested number of machines yet. Apply again in a few minutes."
    }
  }
}

data "aws_subnets" "vpc" {
  count = local.lb == null ? 0 : length(local.lb.subnet_ids) == 0 ? 1 : 0

  filter {
    name   = "vpc-id"
    values = [var.vpc_id]
  }
}

data "aws_subnet" "vpc" {
  for_each = toset(try(data.aws_subnets.vpc[0].ids, []))
  id       = each.value
}

# Subnets chosen for the NLB in public mode; check they're in vpc_id.
data "aws_subnet" "frontend" {
  for_each = toset(try(local.lb.subnet_ids, []))
  id       = each.value

  lifecycle {
    postcondition {
      condition     = self.vpc_id == var.vpc_id
      error_message = "OpenSearch Dashboards frontend subnets must belong to `vpc_id`."
    }
  }
}

resource "aws_lb" "dashboards" {
  count                            = local.lb == null ? 0 : 1
  internal                         = !local.lb_public
  load_balancer_type               = "network"
  ip_address_type                  = "ipv4"
  security_groups                  = local.lb_public ? [aws_security_group.dashboards_frontend[0].id] : null
  subnets                          = local.lb_subnet_ids
  enable_cross_zone_load_balancing = true

  lifecycle {
    precondition {
      condition     = length(distinct([for subnet in data.aws_subnet.frontend : subnet.availability_zone])) == length(data.aws_subnet.frontend)
      error_message = "Select at most one frontend subnet per availability zone."
    }
  }

  tags = {
    Name = "${var.opensearch_model}-dashboards"
  }
}

# New target group whenever the OpenSearch Dashboards machines change.
resource "terraform_data" "dashboards_backends" {
  count            = local.lb == null ? 0 : 1
  triggers_replace = [for machine in data.juju_machine.dashboards : machine.instance_id]

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_lb_target_group" "dashboards" {
  count       = local.lb == null ? 0 : 1
  port        = 5601
  protocol    = local.lb_tls && var.opensearch_dashboards.tls ? "TLS" : "TCP"
  target_type = "instance"
  vpc_id      = var.vpc_id

  health_check {
    protocol = "TCP"
  }

  tags = {
    Name = "${var.opensearch_model}-dashboards"
  }

  lifecycle {
    create_before_destroy = true
    replace_triggered_by  = [terraform_data.dashboards_backends[0]]
  }
}

resource "aws_lb_target_group_attachment" "dashboards" {
  count            = local.lb_target_count
  target_group_arn = aws_lb_target_group.dashboards[0].arn
  target_id        = data.juju_machine.dashboards[count.index].instance_id
  port             = 5601
}

resource "aws_lb_listener" "dashboards" {
  count             = local.lb == null ? 0 : 1
  load_balancer_arn = aws_lb.dashboards[0].arn
  port              = local.lb_port
  protocol          = local.lb_tls ? "TLS" : "TCP"
  certificate_arn   = local.lb.certificate_arn
  ssl_policy        = local.lb_tls ? "ELBSecurityPolicy-TLS13-1-2-2021-06" : null

  # Add the machines and open their firewall before sending traffic to them.
  depends_on = [
    aws_lb_target_group_attachment.dashboards,
    aws_network_interface_sg_attachment.dashboards,
    aws_vpc_security_group_ingress_rule.dashboards_backends,
    aws_vpc_security_group_egress_rule.dashboards_backends,
  ]

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.dashboards[0].arn
  }
}

resource "aws_route53_zone" "dashboards" {
  count = local.lb_dns_name == null || local.lb_public ? 0 : 1
  name  = local.lb_dns_name

  vpc {
    vpc_id = var.vpc_id
  }
}

resource "aws_route53_record" "dashboards" {
  count   = local.lb_dns_name == null || local.lb_public ? 0 : 1
  zone_id = aws_route53_zone.dashboards[0].zone_id
  name    = local.lb_dns_name
  type    = "A"

  alias {
    name                   = aws_lb.dashboards[0].dns_name
    zone_id                = aws_lb.dashboards[0].zone_id
    evaluate_target_health = true
  }
}
