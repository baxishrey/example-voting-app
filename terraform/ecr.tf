resource "aws_ecr_repository" "ecr_repository" {
  for_each = { for svc in var.service_details : svc.service_name => svc if svc.create_ecr_repo == true }

  name = each.value.service_name
}
