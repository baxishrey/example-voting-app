data "aws_region" "current" {
}

data "aws_caller_identity" "current" {

}

locals {
  aws_region          = data.aws_region.current.name
  db_service_name     = var.db_service_name
  redis_service_name  = var.redis_service_name
  worker_service_name = var.worker_service_name
  result_service_name = var.result_service_name
  vote_service_name   = var.vote_service_name
}

variable "public_subnet_cidrs" {
  type        = list(string)
  description = "Public subnet CIDRs"
  default     = ["10.0.0.0/20", "10.0.16.0/20"]
}

variable "private_subnet_cidrs" {
  type        = list(string)
  description = "Private subnet CIDRs"
  default     = ["10.0.128.0/20", "10.0.144.0/20"]
}

variable "app_name" {
  type    = string
  default = "animals-vote-app"
}

variable "db_security_group_name" {
  type    = string
  default = "SG_Database"
}

variable "redis_security_group_name" {
  type    = string
  default = "SG_Redis"
}

variable "result_service_security_group_name" {
  type    = string
  default = "SG_Result_Service"
}

variable "vote_service_security_group_name" {
  type    = string
  default = "SG_Vote_Service"
}

variable "alb_security_group_name" {
  type    = string
  default = "SG_ALB"
}

variable "service_names" {
  type    = list(string)
  default = ["worker", "vote-service", "result-service"]
}

variable "db_service_name" {
  type    = string
  default = "postgres-db"
}

variable "redis_service_name" {
  type    = string
  default = "redis-db"
}

variable "vote_service_name" {
  type    = string
  default = "vote-service"
}

variable "result_service_name" {
  type    = string
  default = "result-service"
}

variable "worker_service_name" {
  type    = string
  default = "worker-service"
}

variable "fargate_cpu" {
  description = "Fargate instance CPU units to provision (1 vCPU = 1024 CPU units)"
  default     = "1024"
}

variable "fargate_memory" {
  description = "Fargate instance memory to provision (in MiB)"
  default     = "2048"
}


variable "ecs_task_execution_role_name" {
  description = "ECS task execution role name"
  default     = "myEcsTaskExecutionRole"
}

variable "app_port_mapping" {
  type = object({
    redis-db       = number
    postgres-db    = number
    vote-service   = number
    result-service = number
  })

  default = {
    redis-db       = 6379
    postgres-db    = 5432
    vote-service   = 80
    result-service = 80
  }
}

variable "alb_port_mapping" {
  type = object({
    vote-service   = number
    result-service = number
  })

  default = {
    vote-service   = 80
    result-service = 81
  }
}

variable "service_details" {
  type = list(object({
    service_name    = string
    create_ecr_repo = bool
    sg_name         = optional(string)
    alb_port        = optional(number)
    app_port        = optional(number)
    allowed_from    = list(string)
    image_name      = optional(string)
  }))

  default = [
    {
      service_name    = "postgres-db"
      sg_name         = "SG_Database"
      app_port        = 5432
      allowed_from    = ["result-service", "worker-service"]
      image_name      = "postgres:9.4"
      create_ecr_repo = false
    },
    {
      service_name    = "redis-db"
      sg_name         = "SG_Redis"
      app_port        = 6379
      allowed_from    = ["vote-service", "worker-service"]
      image_name      = "redis:5.0-alpine3.10"
      create_ecr_repo = false
    },
    {
      service_name    = "vote-service"
      sg_name         = "SG_Vote_Service"
      app_port        = 80
      alb_port        = 80
      allowed_from    = ["alb"]
      create_ecr_repo = true
    },
    {
      service_name    = "result-service"
      sg_name         = "SG_Result_Service"
      app_port        = 80
      alb_port        = 81
      allowed_from    = ["alb"]
      create_ecr_repo = true
    },
    {
      service_name    = "worker-service"
      sg_name         = "SG_Worker_service"
      allowed_from    = []
      create_ecr_repo = true
    }
  ]
}
