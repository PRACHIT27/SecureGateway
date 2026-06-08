# ── ECS CLUSTER ──────────────────────────────────────────────────

resource "aws_ecs_cluster" "main" {
  name = "${var.project_name}-cluster"

  # Container Insights — per-task CPU and memory metrics in CloudWatch
  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = { Name = "${var.project_name}-cluster" }
}

resource "aws_ecs_cluster_capacity_providers" "main" {
  cluster_name       = aws_ecs_cluster.main.name
  capacity_providers = ["FARGATE"]

  default_capacity_provider_strategy {
    capacity_provider = "FARGATE"
    weight            = 1
  }
}

# ── CLOUDWATCH LOG GROUPS ─────────────────────────────────────────

resource "aws_cloudwatch_log_group" "sast" {
  name              = "/ecs/${var.project_name}/sast-worker"
  retention_in_days = 7
  tags              = { Name = "SAST logs" }
}

resource "aws_cloudwatch_log_group" "pentest" {
  name              = "/ecs/${var.project_name}/pentest-worker"
  retention_in_days = 7
  tags              = { Name = "Pentest logs" }
}

# ── TASK DEFINITIONS ─────────────────────────────────────────────

resource "aws_ecs_task_definition" "sast_worker" {
  family                   = "${var.project_name}-sast-worker"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.fargate_cpu_sast
  memory                   = var.fargate_memory_sast
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn
  task_role_arn            = aws_iam_role.sast_task.arn

  container_definitions = jsonencode([{
    name      = "sast-worker"
    image     = "${aws_ecr_repository.sast_scanner.repository_url}:latest"
    essential = true

    environment = [
      { name = "QUEUE_URL",        value = aws_sqs_queue.sast_queue.url },
      { name = "DYNAMODB_TABLE",   value = aws_dynamodb_table.scans.name },
      { name = "S3_BUCKET",        value = aws_s3_bucket.reports.bucket },
      { name = "AWS_REGION",       value = var.aws_region },
      { name = "MAX_WAIT_SECONDS", value = "600" }
    ]

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.sast.name
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = "sast"
      }
    }
  }])

  tags = { Name = "SAST Worker Task" }
}

resource "aws_ecs_task_definition" "pentest_worker" {
  family                   = "${var.project_name}-pentest-worker"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.fargate_cpu_pentest
  memory                   = var.fargate_memory_pentest
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn
  task_role_arn            = aws_iam_role.pentest_task.arn

  container_definitions = jsonencode([{
    name      = "pentest-worker"
    image     = "${aws_ecr_repository.pentest_worker.repository_url}:latest"
    essential = true

    environment = [
      { name = "QUEUE_URL",        value = aws_sqs_queue.pentest_queue.url },
      { name = "DYNAMODB_TABLE",   value = aws_dynamodb_table.scans.name },
      { name = "S3_BUCKET",        value = aws_s3_bucket.reports.bucket },
      { name = "AWS_REGION",       value = var.aws_region },
      { name = "MAX_WAIT_SECONDS", value = "600" },
      { name = "ECS_CLUSTER",      value = aws_ecs_cluster.main.name },
      { name = "TARGET_SUBNET",    value = aws_subnet.private.id },
      { name = "TARGET_SG",        value = aws_security_group.fargate.id }
    ]

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.pentest.name
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = "pentest"
      }
    }
  }])

  tags = { Name = "Pentest Worker Task" }
}

# ── CLOUDWATCH ALARMS ─────────────────────────────────────────────
# Alert on high memory/CPU — catches right-sizing issues early

resource "aws_cloudwatch_metric_alarm" "sast_memory_high" {
  alarm_name          = "${var.project_name}-sast-memory-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "MemoryUtilized"
  namespace           = "ECS/ContainerInsights"
  period              = 60
  statistic           = "Average"
  threshold           = 80
  alarm_description   = "SAST task memory above 80% — consider increasing fargate_memory_sast"
  alarm_actions       = [aws_sns_topic.alerts.arn]

  dimensions = {
    ClusterName = aws_ecs_cluster.main.name
    TaskDefinitionFamily = "${var.project_name}-sast-worker"
  }
}

resource "aws_cloudwatch_metric_alarm" "pentest_memory_high" {
  alarm_name          = "${var.project_name}-pentest-memory-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "MemoryUtilized"
  namespace           = "ECS/ContainerInsights"
  period              = 60
  statistic           = "Average"
  threshold           = 80
  alarm_description   = "Pentest task memory above 80% — consider increasing fargate_memory_pentest"
  alarm_actions       = [aws_sns_topic.alerts.arn]

  dimensions = {
    ClusterName = aws_ecs_cluster.main.name
    TaskDefinitionFamily = "${var.project_name}-pentest-worker"
  }
}
