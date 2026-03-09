output "s3_bucket_name" {
  description = "S3 bucket for export data"
  value       = aws_s3_bucket.export_data.bucket
}

output "s3_bucket_arn" {
  description = "S3 bucket ARN"
  value       = aws_s3_bucket.export_data.arn
}

output "ecr_repository_url" {
  description = "ECR repository URL — push Docker image here"
  value       = aws_ecr_repository.export_runner.repository_url
}

output "ecs_cluster_name" {
  description = "ECS cluster name"
  value       = aws_ecs_cluster.export.name
}

output "ecs_task_definition_arn" {
  description = "ECS task definition ARN"
  value       = aws_ecs_task_definition.export_runner.arn
}

output "security_group_id" {
  description = "Fargate task security group ID"
  value       = aws_security_group.fargate_task.id
}

output "log_group_name" {
  description = "CloudWatch log group for task logs"
  value       = aws_cloudwatch_log_group.export_runner.name
}

# ---- Convenience: Run task command ----
output "run_task_command" {
  description = "AWS CLI command to trigger the export"
  value       = <<-EOT
    aws ecs run-task \
      --cluster ${aws_ecs_cluster.export.name} \
      --task-definition ${aws_ecs_task_definition.export_runner.family} \
      --launch-type FARGATE \
      --network-configuration "awsvpcConfiguration={subnets=[${join(",", var.subnet_ids)}],securityGroups=[${aws_security_group.fargate_task.id}],assignPublicIp=ENABLED}" \
      --region ${var.aws_region}
  EOT
}
