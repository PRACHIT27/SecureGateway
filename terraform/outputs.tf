output "api_gateway_url" {
  description = "API Gateway base URL — give this to customers"
  value       = "https://${aws_api_gateway_rest_api.main.id}.execute-api.${var.aws_region}.amazonaws.com/${aws_api_gateway_stage.main.stage_name}"
}

output "api_key_id" {
  description = "API key ID — retrieve value with: aws apigateway get-api-key --api-key <id> --include-value"
  value       = aws_api_gateway_api_key.main.id
}

output "ecr_sast_uri" {
  description = "ECR URI for SAST scanner image"
  value       = aws_ecr_repository.sast_scanner.repository_url
}

output "ecr_pentest_uri" {
  description = "ECR URI for pentest worker image"
  value       = aws_ecr_repository.pentest_worker.repository_url
}

output "ecr_client_scans_uri" {
  description = "ECR URI for client scan images — give this to customers"
  value       = aws_ecr_repository.client_scans.repository_url
}

output "ecs_cluster_name" {
  description = "ECS cluster name"
  value       = aws_ecs_cluster.main.name
}

output "sast_queue_url" {
  description = "SQS SAST queue URL"
  value       = aws_sqs_queue.sast_queue.url
}

output "pentest_queue_url" {
  description = "SQS pentest queue URL"
  value       = aws_sqs_queue.pentest_queue.url
}

output "dynamodb_scans_table" {
  description = "DynamoDB scans table name"
  value       = aws_dynamodb_table.scans.name
}

output "s3_reports_bucket" {
  description = "S3 reports bucket name"
  value       = aws_s3_bucket.reports.bucket
}

output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.main.id
}

output "private_subnet_id" {
  description = "Private subnet ID — Fargate tasks run here"
  value       = aws_subnet.private.id
}
