# Copyright 2026 Canonical Ltd.
# See LICENSE file for licensing details.

resource "terraform_data" "dashboards_units" {
  count = local.lb == null ? 0 : 1
  input = var.opensearch_dashboards.units
}

data "juju_application" "dashboards" {
  count      = local.lb == null ? 0 : 1
  model_uuid = juju_model.opensearch[var.opensearch_model].uuid
  name       = module.opensearch.app_names.opensearch_dashboards

  depends_on = [terraform_data.dashboards_units]

  lifecycle {
    postcondition {
      condition     = length(self.machines) == var.opensearch_dashboards.units
      error_message = "OpenSearch Dashboards doesn't have `opensearch_dashboards.units` machines yet. Apply again in a few minutes."
    }
  }
}

data "juju_machine" "dashboards" {
  count                 = local.lb_target_count
  model_uuid            = juju_model.opensearch[var.opensearch_model].uuid
  machine_id            = sort(tolist(data.juju_application.dashboards[0].machines))[count.index]
  wait_for_ip_addresses = ["private"]
}

data "aws_subnets" "vpc" {
  count = local.lb == null ? 0 : 1

  filter {
    name   = "vpc-id"
    values = [var.vpc_id]
  }
}

data "aws_subnet" "vpc" {
  for_each = toset(try(data.aws_subnets.vpc[0].ids, []))
  id       = each.value
}

resource "aws_lb" "dashboards" {
  count                            = local.lb == null ? 0 : 1
  internal                         = true
  load_balancer_type               = "network"
  subnets                          = local.lb_subnet_ids
  enable_cross_zone_load_balancing = true

  tags = {
    Name = "${var.opensearch_model}-dashboards"
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

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.dashboards[0].arn
  }
}

resource "aws_route53_zone" "dashboards" {
  count = local.lb_dns_name == null ? 0 : 1
  name  = local.lb_dns_name

  vpc {
    vpc_id = var.vpc_id
  }
}

resource "aws_route53_record" "dashboards" {
  count   = local.lb_dns_name == null ? 0 : 1
  zone_id = aws_route53_zone.dashboards[0].zone_id
  name    = local.lb_dns_name
  type    = "A"

  alias {
    name                   = aws_lb.dashboards[0].dns_name
    zone_id                = aws_lb.dashboards[0].zone_id
    evaluate_target_health = true
  }
}
