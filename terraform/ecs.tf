resource "aws_service_discovery_http_namespace" "main" {
  name = "app"
}

resource "aws_ecs_cluster" "main" {
  name = "${var.app_name}-cluster"
  service_connect_defaults {
    namespace = aws_service_discovery_http_namespace.main.arn
  }
}

resource "aws_ecs_cluster_capacity_providers" "main" {
  cluster_name = aws_ecs_cluster.main.name

  capacity_providers = ["FARGATE", "FARGATE_SPOT"]

  default_capacity_provider_strategy {
    base              = 1
    weight            = 100
    capacity_provider = "FARGATE"
  }
}

resource "aws_ecs_task_definition" "service_task_definitions" {
  for_each = { for svc in var.service_details : svc.service_name => svc if svc.create_ecr_repo == true }

  family                   = each.key
  requires_compatibilities = ["FARGATE"]
  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }

  cpu                = var.fargate_cpu
  memory             = var.fargate_memory
  network_mode       = "awsvpc"
  execution_role_arn = aws_iam_role.ecs_task_execution_role.arn

  container_definitions = templatefile("./taskdefinitions/${var.app_name}.json.tftpl", {
    app_name       = each.key
    app_image      = aws_ecr_repository.ecr_repository[each.key].repository_url
    fargate_cpu    = var.fargate_cpu
    fargate_memory = var.fargate_memory
    aws_region     = local.aws_region
    port_mappings = each.value.app_port != null ? jsonencode([{
      "containerPort" = each.value.app_port
      "name"          = each.key
      "protocol"      = "tcp"
    }]) : null
    environment = null
  })

  tags = {
    Port               = each.value.app_port
    Load_Balancer_Port = each.value.alb_port
  }
}

resource "aws_ecs_task_definition" "db_task_definitions" {
  for_each                 = { for svc in var.service_details : svc.service_name => svc if svc.image_name != null }
  family                   = each.key
  requires_compatibilities = ["FARGATE"]
  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }

  cpu                = var.fargate_cpu
  memory             = var.fargate_memory
  network_mode       = "awsvpc"
  execution_role_arn = aws_iam_role.ecs_task_execution_role.arn

  container_definitions = templatefile("./taskdefinitions/${var.app_name}.json.tftpl", {
    app_name       = each.key
    app_image      = each.value.image_name
    fargate_cpu    = var.fargate_cpu
    fargate_memory = var.fargate_memory
    aws_region     = local.aws_region
    port_mappings = jsonencode([{
      "containerPort" = each.value.app_port
      "name"          = each.key
      "protocol"      = "tcp"
    }])
    environment = each.key == var.db_service_name ? jsonencode([
      {
        "name"  = "POSTGRES_USER",
        "value" = "postgres"
      },
      {
        "name"  = "POSTGRES_PASSWORD",
        "value" = "postgres"
      }
    ]) : null
  })

  tags = {
    Port = each.value.app_port
  }
}

resource "aws_cloudwatch_log_group" "log_groups" {
  for_each = { for svc in var.service_details : svc.service_name => svc if svc.create_ecr_repo == true }
  name     = "/ecs/${each.key}"
}

resource "aws_cloudwatch_log_group" "db_log_groups" {
  for_each = { for svc in var.service_details : svc.service_name => svc if svc.image_name != null }
  name     = "/ecs/${each.key}"
}

resource "aws_ecs_service" "db_services" {
  for_each = aws_ecs_task_definition.db_task_definitions

  name            = each.value.family
  cluster         = aws_ecs_cluster.main.id
  task_definition = each.value.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = aws_subnet.private_subnet.*.id
    security_groups  = [aws_security_group.security_groups[each.value.family].id]
    assign_public_ip = false
  }

  service_connect_configuration {
    enabled   = true
    namespace = aws_service_discovery_http_namespace.main.arn
    service {
      port_name = each.value.family
      client_alias {
        port = each.value.tags.Port
      }
    }
  }
}

resource "aws_ecs_service" "app_service_definitions" {
  for_each = aws_ecs_task_definition.service_task_definitions

  name            = each.value.family
  cluster         = aws_ecs_cluster.main.id
  task_definition = each.value.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = aws_subnet.private_subnet.*.id
    security_groups  = [aws_security_group.security_groups[each.value.family].id]
    assign_public_ip = false
  }

  service_connect_configuration {
    enabled   = true
    namespace = aws_service_discovery_http_namespace.main.arn
    dynamic "service" {
      for_each = { for svc in var.service_details : svc.service_name => svc if svc.app_port != null && svc.service_name == each.value.family }
      content {
        port_name = service.value.service_name
        client_alias {
          port = service.value.app_port
        }
      }
    }

  }

  dynamic "load_balancer" {
    for_each = { for svc in var.service_details : svc.service_name => svc if svc.alb_port != null && svc.service_name == each.value.family }
    content {
      container_name   = load_balancer.value.service_name
      container_port   = load_balancer.value.app_port
      target_group_arn = aws_lb_target_group.app_target_groups[load_balancer.value.service_name].arn

    }
  }
}
