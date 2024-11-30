data "aws_iam_policy_document" "assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["codebuild.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "code_build_role" {
  name               = "codebuild_role"
  assume_role_policy = data.aws_iam_policy_document.assume_role.json
}

data "aws_iam_policy_document" "code_build_policy_document" {
  statement {
    effect = "Allow"

    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]

    resources = ["*"]
  }

  statement {
    effect = "Allow"

    actions = [
      "ec2:CreateNetworkInterface",
      "ec2:DescribeDhcpOptions",
      "ec2:DescribeNetworkInterfaces",
      "ec2:DeleteNetworkInterface",
      "ec2:DescribeSubnets",
      "ec2:DescribeSecurityGroups",
      "ec2:DescribeVpcs",
    ]

    resources = ["*"]
  }

  statement {
    effect = "Allow"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:CompleteLayerUpload",
      "ecr:GetAuthorizationToken",
      "ecr:InitiateLayerUpload",
      "ecr:PutImage",
      "ecr:UploadLayerPart"
    ]
    resources = ["*"]
  }


  statement {
    effect    = "Allow"
    actions   = ["ec2:CreateNetworkInterfacePermission"]
    resources = ["arn:aws:ec2:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:network-interface/*"]

    condition {
      test     = "StringEquals"
      variable = "ec2:Subnet"

      values = aws_subnet.private_subnet.*.arn
    }

    condition {
      test     = "StringEquals"
      variable = "ec2:AuthorizedService"
      values   = ["codebuild.amazonaws.com"]
    }
  }

  statement {
    effect    = "Allow"
    resources = ["*"]
    actions = [
      "codestar-connections:GetConnectionToken",
      "codestar-connections:GetConnection",
      "codeconnections:GetConnectionToken",
      "codeconnections:GetConnection",
      "codeconnections:UseConnection"
    ]
  }
}

resource "aws_iam_role_policy" "code_build_role_policy" {
  role   = aws_iam_role.code_build_role.name
  policy = data.aws_iam_policy_document.code_build_policy_document.json
}

resource "aws_codebuild_project" "build_project" {
  name          = "${var.app_name}-build"
  build_timeout = 5
  service_role  = aws_iam_role.code_build_role.arn

  artifacts {
    type = "NO_ARTIFACTS"
  }

  environment {
    compute_type    = "BUILD_GENERAL1_SMALL"
    image           = "aws/codebuild/standard:7.0"
    type            = "LINUX_CONTAINER"
    privileged_mode = true

    environment_variable {
      name  = "AWS_DEFAULT_REGION"
      value = data.aws_region.current.name
    }

    environment_variable {
      name  = "AWS_ACCOUNT_ID"
      value = data.aws_caller_identity.current.account_id
    }

    environment_variable {
      name  = "IMAGE_TAG"
      value = "latest"
    }

    environment_variable {
      name  = "WORKER_SERVICE_IMAGE"
      value = var.worker_service_name
    }

    environment_variable {
      name  = "RESULT_SERVICE_IMAGE"
      value = var.result_service_name
    }

    environment_variable {
      name  = "VOTE_SERVICE_IMAGE"
      value = var.vote_service_name
    }

  }

  logs_config {
    cloudwatch_logs {
      group_name  = "${var.app_name}-log-group"
      stream_name = "${var.app_name}-log-stream"
    }
  }

  source {
    type            = "GITHUB"
    location        = "https://github.com/baxishrey/example-voting-app.git"
    git_clone_depth = 1
    buildspec       = "buildspec.yml"
  }

  source_version = "master"

  vpc_config {
    vpc_id = aws_vpc.main.id

    subnets = aws_subnet.private_subnet.*.id

    security_group_ids = [
      aws_security_group.alb_security_group.id
    ]
  }

}
