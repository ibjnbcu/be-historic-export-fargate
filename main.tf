###############################################################################
# BE Historic Data Export Infrastructure
# Ticket: DevOps Board - Historic Export Processing
#
# Setup: ECS Fargate (runs export script on demand) + S3 (stores output)
# Trigger: AWS CLI → aws ecs run-task
# Scripts: export.sh (shell) → export.py (python) + sites.txt
###############################################################################

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "be-historic-export"
      Team        = "backend-engineering"
      ManagedBy   = "terraform"
      Environment = var.environment
    }
  }
}

# ---------------------------------------------------------------------------
# Data Sources
# ---------------------------------------------------------------------------
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# ---------------------------------------------------------------------------
# S3 Bucket — XML/CSV Data Storage (60-70 GB)
# ---------------------------------------------------------------------------
resource "aws_s3_bucket" "export_data" {
  bucket = "${var.project_prefix}-data-${var.environment}-${data.aws_caller_identity.current.account_id}"

  tags = { Name = "BE Historic Export Data" }
}

resource "aws_s3_bucket_versioning" "export_data" {
  bucket = aws_s3_bucket.export_data.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_lifecycle_configuration" "export_data" {
  bucket = aws_s3_bucket.export_data.id

  rule {
    id     = "expire-old-exports"
    status = "Enabled"
    filter {}

    expiration { days = var.s3_expiration_days }
    noncurrent_version_expiration { noncurrent_days = 30 }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "export_data" {
  bucket = aws_s3_bucket.export_data.id
  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "aws:kms" }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "export_data" {
  bucket                  = aws_s3_bucket.export_data.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# S3 Access Logging
resource "aws_s3_bucket" "access_logs" {
  bucket = "${var.project_prefix}-access-logs-${var.environment}-${data.aws_caller_identity.current.account_id}"
  tags   = { Name = "BE Historic Export Access Logs" }
}

resource "aws_s3_bucket_public_access_block" "access_logs" {
  bucket                  = aws_s3_bucket.access_logs.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "access_logs" {
  bucket = aws_s3_bucket.access_logs.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "access_logs" {
  bucket = aws_s3_bucket.access_logs.id
  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "aws:kms" }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "access_logs" {
  bucket = aws_s3_bucket.access_logs.id

  rule {
    id     = "expire-logs"
    status = "Enabled"
    filter {}
    expiration { days = 90 }
    abort_incomplete_multipart_upload { days_after_initiation = 7 }
  }
}

resource "aws_s3_bucket_logging" "export_data" {
  bucket        = aws_s3_bucket.export_data.id
  target_bucket = aws_s3_bucket.access_logs.id
  target_prefix = "s3-access-logs/"
}

# ---------------------------------------------------------------------------
# ECR Repository — Stores the Docker image
# ---------------------------------------------------------------------------
resource "aws_ecr_repository" "export_runner" {
  name                 = "${var.project_prefix}-runner"
  image_tag_mutability = "IMMUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "KMS"
  }

  tags = { Name = "BE Historic Export Runner" }
}

resource "aws_ecr_lifecycle_policy" "export_runner" {
  repository = aws_ecr_repository.export_runner.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep only last 5 images"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = 5
        }
        action = { type = "expire" }
      }
    ]
  })
}

# ---------------------------------------------------------------------------
# KMS Key — CloudWatch Logs encryption
# ---------------------------------------------------------------------------
resource "aws_kms_key" "cloudwatch" {
  description             = "KMS key for BE export CloudWatch logs"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "EnableRootAccount"
        Effect    = "Allow"
        Principal = { AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root" }
        Action    = "kms:*"
        Resource  = "*"
      },
      {
        Sid       = "AllowCloudWatchLogs"
        Effect    = "Allow"
        Principal = { Service = "logs.${data.aws_region.current.name}.amazonaws.com" }
        Action = [
          "kms:Encrypt*",
          "kms:Decrypt*",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:Describe*"
        ]
        Resource = "*"
        Condition = {
          ArnEquals = {
            "kms:EncryptionContext:aws:logs:arn" = "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/ecs/${var.project_prefix}"
          }
        }
      }
    ]
  })

  tags = { Name = "${var.project_prefix}-cloudwatch-key" }
}

resource "aws_kms_alias" "cloudwatch" {
  name          = "alias/${var.project_prefix}-cloudwatch"
  target_key_id = aws_kms_key.cloudwatch.key_id
}

# ---------------------------------------------------------------------------
# CloudWatch Log Group — Task logs (365 day retention, KMS encrypted)
# ---------------------------------------------------------------------------
resource "aws_cloudwatch_log_group" "export_runner" {
  name              = "/ecs/${var.project_prefix}"
  retention_in_days = 365
  kms_key_id        = aws_kms_key.cloudwatch.arn

  tags = { Name = "BE Historic Export Logs" }
}

# ---------------------------------------------------------------------------
# IAM — Task Execution Role (ECS pulls image + sends logs)
# ---------------------------------------------------------------------------
resource "aws_iam_role" "ecs_execution_role" {
  name = "${var.project_prefix}-ecs-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_execution_managed" {
  role       = aws_iam_role.ecs_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# ---------------------------------------------------------------------------
# IAM — Task Role (the container's permissions — S3 read/write)
# ---------------------------------------------------------------------------
resource "aws_iam_role" "ecs_task_role" {
  name = "${var.project_prefix}-ecs-task-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "task_s3_access" {
  name = "${var.project_prefix}-s3-access"
  role = aws_iam_role.ecs_task_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:ListBucket",
          "s3:DeleteObject"
        ]
        Resource = [
          aws_s3_bucket.export_data.arn,
          "${aws_s3_bucket.export_data.arn}/*"
        ]
      }
    ]
  })
}

# ---------------------------------------------------------------------------
# ECS Cluster
# ---------------------------------------------------------------------------
resource "aws_ecs_cluster" "export" {
  name = "${var.project_prefix}-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = { Name = "BE Historic Export Cluster" }
}

# ---------------------------------------------------------------------------
# ECS Task Definition — Fargate
# ---------------------------------------------------------------------------
resource "aws_ecs_task_definition" "export_runner" {
  family                   = "${var.project_prefix}-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.fargate_cpu
  memory                   = var.fargate_memory
  execution_role_arn       = aws_iam_role.ecs_execution_role.arn
  task_role_arn            = aws_iam_role.ecs_task_role.arn

  ephemeral_storage {
    size_in_gib = var.ephemeral_storage_gb
  }

  volume {
    name = "tmp-storage"
  }

  container_definitions = jsonencode([
    {
      name                   = "export-runner"
      image                  = "${aws_ecr_repository.export_runner.repository_url}:${var.image_tag}"
      essential              = true
      readonlyRootFilesystem = true

      mountPoints = [
        {
          sourceVolume  = "tmp-storage"
          containerPath = "/tmp"
          readOnly      = false
        }
      ]

      environment = [
        { name = "EXPORT_S3_BUCKET", value = aws_s3_bucket.export_data.bucket },
        { name = "AWS_DEFAULT_REGION", value = var.aws_region }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.export_runner.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "export"
        }
      }
    }
  ])

  tags = { Name = "BE Historic Export Task" }
}

# ---------------------------------------------------------------------------
# Security Group — Fargate task (outbound only, no inbound needed)
# ---------------------------------------------------------------------------
resource "aws_security_group" "fargate_task" {
  name        = "${var.project_prefix}-fargate-sg"
  description = "SG for BE historic export Fargate task"
  vpc_id      = var.vpc_id

  # No inbound needed — task only makes outbound calls

  egress {
    description = "Allow all outbound (curl RSS feeds + S3 upload)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project_prefix}-fargate-sg" }
}
