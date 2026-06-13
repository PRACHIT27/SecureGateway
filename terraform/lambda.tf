# ── LAMBDA PLACEHOLDER ZIP ───────────────────────────────────────

data "archive_file" "placeholder" {
  type        = "zip"
  output_path = "${path.module}/placeholder.zip"

  source {
    content  = "exports.handler = async () => ({ statusCode: 200, body: 'placeholder' });"
    filename = "index.js"
  }
}

# ── TRIGGER LAMBDA (Lambda 1) ─────────────────────────────────────

resource "aws_lambda_function" "trigger" {
  function_name = "${var.project_name}-trigger"
  role          = data.aws_iam_role.lab_role.arn
  handler       = "index.handler"
  runtime       = "nodejs18.x"
  timeout       = 30
  memory_size   = 256

  filename         = data.archive_file.placeholder.output_path
  source_code_hash = data.archive_file.placeholder.output_base64sha256

  # Fix 9: Add reserved concurrency to prevent runaway scaling
  reserved_concurrent_executions = 10

  environment {
    variables = {
      SAST_QUEUE_URL    = aws_sqs_queue.sast_queue.url
      PENTEST_QUEUE_URL = aws_sqs_queue.pentest_queue.url
      DYNAMODB_TABLE    = aws_dynamodb_table.scans.name
      CONFIG_TABLE      = aws_dynamodb_table.config.name
      ECS_CLUSTER       = aws_ecs_cluster.main.name
      SAST_TASK_DEF     = aws_ecs_task_definition.sast_worker.arn
      PENTEST_TASK_DEF  = aws_ecs_task_definition.pentest_worker.arn
      PRIVATE_SUBNET    = aws_subnet.private.id
      FARGATE_SG        = aws_security_group.fargate.id
      AWS_ACCOUNT_ID    = data.aws_caller_identity.current.account_id
    }
  }

  tags = { Name = "Trigger Lambda" }
}

resource "aws_cloudwatch_log_group" "lambda_trigger" {
  name              = "/aws/lambda/${aws_lambda_function.trigger.function_name}"
  retention_in_days = 7
}

# ── SEVERITY CHECK LAMBDA ─────────────────────────────────────────

resource "aws_lambda_function" "severity_check" {
  function_name = "${var.project_name}-severity-check"
  role          = data.aws_iam_role.lab_role.arn
  handler       = "index.handler"
  runtime       = "nodejs18.x"
  timeout       = 30
  memory_size   = 256

  filename         = data.archive_file.placeholder.output_path
  source_code_hash = data.archive_file.placeholder.output_base64sha256

  # Fix 9: Add reserved concurrency to prevent runaway scaling
  reserved_concurrent_executions = 10

  environment {
    variables = {
      PENTEST_QUEUE_URL = aws_sqs_queue.pentest_queue.url
      DYNAMODB_TABLE    = aws_dynamodb_table.scans.name
      CONFIG_TABLE      = aws_dynamodb_table.config.name
      SNS_TOPIC_ARN     = aws_sns_topic.alerts.arn
    }
  }

  tags = { Name = "Severity Check Lambda" }
}

resource "aws_cloudwatch_log_group" "lambda_severity" {
  name              = "/aws/lambda/${aws_lambda_function.severity_check.function_name}"
  retention_in_days = 7
}

resource "aws_lambda_event_source_mapping" "severity_check" {
  event_source_arn  = aws_dynamodb_table.scans.stream_arn
  function_name     = aws_lambda_function.severity_check.arn
  starting_position = "LATEST"
  batch_size        = 1

  filter_criteria {
    filter {
      pattern = jsonencode({
        dynamodb = {
          NewImage = {
            status = { S = ["complete"] }
          }
        }
      })
    }
  }
}

# ── RESULTS LAMBDA (Lambda 2) ─────────────────────────────────────

resource "aws_lambda_function" "results" {
  function_name = "${var.project_name}-results"
  role          = data.aws_iam_role.lab_role.arn
  handler       = "index.handler"
  runtime       = "nodejs18.x"
  timeout       = 30
  memory_size   = 256

  filename         = data.archive_file.placeholder.output_path
  source_code_hash = data.archive_file.placeholder.output_base64sha256

  # Fix 9: Add reserved concurrency to prevent runaway scaling
  reserved_concurrent_executions = 10

  environment {
    variables = {
      DYNAMODB_TABLE = aws_dynamodb_table.scans.name
      S3_BUCKET      = aws_s3_bucket.reports.bucket
      SNS_TOPIC_ARN  = aws_sns_topic.alerts.arn
      GITHUB_SECRET_ARN = aws_secretsmanager_secret.github_token.arn
    }
  }

  tags = { Name = "Results Lambda" }
}

resource "aws_cloudwatch_log_group" "lambda_results" {
  name              = "/aws/lambda/${aws_lambda_function.results.function_name}"
  retention_in_days = 7
}

resource "aws_lambda_event_source_mapping" "results" {
  event_source_arn  = aws_dynamodb_table.scans.stream_arn
  function_name     = aws_lambda_function.results.arn
  starting_position = "LATEST"
  batch_size        = 1

  filter_criteria {
    filter {
      pattern = jsonencode({
        dynamodb = {
          NewImage = {
            overall_status = { S = ["complete", "failed"] }
          }
        }
      })
    }
  }
}
