data "aws_availability_zones" "available" {

}

locals {
  ingress_rule_details = flatten([
    for svc in var.service_details : [
      for source in svc.allowed_from : {
        service_name = svc.service_name
        app_port     = svc.app_port
        allowed_from = source
      } if svc.app_port != null
    ]
  ])
}

resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags = {
    "Name" = "${var.app_name}-vpc"
  }
}

resource "aws_subnet" "public_subnet" {
  count                   = length(slice(data.aws_availability_zones.available.names, 0, 2))
  vpc_id                  = aws_vpc.main.id
  cidr_block              = element(var.public_subnet_cidrs, count.index)
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.app_name}-subnet-public${count.index + 1}-${data.aws_availability_zones.available.names[count.index]}"
  }
}

resource "aws_subnet" "private_subnet" {
  count             = length(slice(data.aws_availability_zones.available.names, 0, 2))
  vpc_id            = aws_vpc.main.id
  cidr_block        = element(var.private_subnet_cidrs, count.index)
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = {
    Name = "${var.app_name}-subnet-private${count.index + 1}-${data.aws_availability_zones.available.names[count.index]}"
  }
}

resource "aws_internet_gateway" "internet_gateway" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.app_name}-igw"
  }
}

resource "aws_eip" "nat_gw" {
  depends_on = [aws_internet_gateway.internet_gateway]
  tags = {
    Name = "${var.app_name}-eip-${data.aws_availability_zones.available.names[0]}"
  }
  domain = "vpc"
}

resource "aws_nat_gateway" "nat_gateway" {
  subnet_id     = element(aws_subnet.public_subnet.*.id, 0)
  allocation_id = aws_eip.nat_gw.id
  depends_on    = [aws_internet_gateway.internet_gateway]

  tags = {
    Name = "${var.app_name}-nat-public1-${data.aws_availability_zones.available.names[0]}"
  }
}

resource "aws_route_table" "public_rtb" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.internet_gateway.id
  }

  route {
    cidr_block = aws_vpc.main.cidr_block
    gateway_id = "local"
  }

  tags = {
    Name = "${var.app_name}-rtb-public"
  }
}

resource "aws_route_table_association" "public_rtb_association" {
  route_table_id = aws_route_table.public_rtb.id
  count          = length(aws_subnet.public_subnet)
  subnet_id      = element(aws_subnet.public_subnet.*.id, count.index)
}

resource "aws_route_table" "private_rtb" {
  count  = length(var.private_subnet_cidrs)
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat_gateway.id
  }

  route {
    cidr_block = aws_vpc.main.cidr_block
    gateway_id = "local"
  }

  tags = {
    Name = "${var.app_name}-rtb-private${count.index + 1}-${data.aws_availability_zones.available.names[count.index]}"
  }
}

resource "aws_route_table_association" "private_rtb_association" {
  count          = length(aws_subnet.public_subnet)
  route_table_id = element(aws_route_table.private_rtb.*.id, count.index)
  subnet_id      = element(aws_subnet.private_subnet.*.id, count.index)
}

resource "aws_security_group" "security_groups" {
  for_each = { for svc in var.service_details : svc.service_name => svc if svc.sg_name != null }
  name     = each.value.sg_name
  vpc_id   = aws_vpc.main.id

  tags = {
    Name    = each.value.sg_name
    Service = each.key
    App     = var.app_name
  }
}

resource "aws_security_group" "alb_security_group" {
  name   = var.alb_security_group_name
  vpc_id = aws_vpc.main.id

  tags = {
    Name    = var.alb_security_group_name
    Service = "ALB"
    App     = var.app_name
  }
}

resource "aws_vpc_security_group_egress_rule" "service_egress_rules" {
  for_each = aws_security_group.security_groups

  security_group_id = each.value.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

resource "aws_vpc_security_group_egress_rule" "alb_egress_rule" {
  security_group_id = aws_security_group.alb_security_group.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

resource "aws_vpc_security_group_ingress_rule" "ingress_rules" {
  for_each = { for rule in local.ingress_rule_details : "${rule.service_name}-from-${rule.allowed_from}" => rule }

  security_group_id            = aws_security_group.security_groups[each.value.service_name].id
  ip_protocol                  = "tcp"
  from_port                    = each.value.app_port
  to_port                      = each.value.app_port
  referenced_security_group_id = each.value.allowed_from != "alb" ? aws_security_group.security_groups[each.value.allowed_from].id : aws_security_group.alb_security_group.id
}

resource "aws_vpc_security_group_ingress_rule" "alb_ingress_rule" {
  security_group_id = aws_security_group.alb_security_group.id
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 81
  cidr_ipv4         = "0.0.0.0/0"
}
