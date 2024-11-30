resource "aws_lb" "main" {
  name            = var.app_name
  subnets         = aws_subnet.public_subnet.*.id
  security_groups = [aws_security_group.alb_security_group.id]
}

resource "aws_lb_target_group" "app_target_groups" {
  for_each    = { for svc in var.service_details : svc.service_name => svc if svc.alb_port != null }
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "ip"

  name = "${each.key}-target-group"
  port = each.value.app_port
}

resource "aws_lb_listener" "app_lb_listeners" {
  for_each          = { for svc in var.service_details : svc.service_name => svc if svc.alb_port != null }
  load_balancer_arn = aws_lb.main.arn
  protocol          = "HTTP"
  port              = each.value.alb_port
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app_target_groups[each.key].arn
  }
}
