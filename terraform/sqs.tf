# ── DEAD LETTER QUEUES ───────────────────────────────────────────

resource "aws_sqs_queue" "sast_dlq" {
  name                      = "${var.project_name}-sast-dlq"
  message_retention_seconds = 1209600 # 14 days

  tags = { Name = "SAST DLQ" }
}

resource "aws_sqs_queue" "pentest_dlq" {
  name                      = "${var.project_name}-pentest-dlq"
  message_retention_seconds = 1209600

  tags = { Name = "Pentest DLQ" }
}

# ── MAIN QUEUES ──────────────────────────────────────────────────

resource "aws_sqs_queue" "sast_queue" {
  name                       = "${var.project_name}-sast-queue"
  visibility_timeout_seconds = var.sqs_visibility_timeout_sast
  message_retention_seconds  = 86400 # 1 day
  receive_wait_time_seconds  = 20    # long polling enabled

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.sast_dlq.arn
    maxReceiveCount     = 3
  })

  tags = { Name = "SAST Queue" }
}

resource "aws_sqs_queue" "pentest_queue" {
  name                       = "${var.project_name}-pentest-queue"
  visibility_timeout_seconds = var.sqs_visibility_timeout_pentest
  message_retention_seconds  = 86400
  receive_wait_time_seconds  = 20

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.pentest_dlq.arn
    maxReceiveCount     = 3
  })

  tags = { Name = "Pentest Queue" }
}

# ── DLQ CLOUDWATCH ALARMS ────────────────────────────────────────
# Fire SNS alert when any message lands in a DLQ
# means a scan failed 3 times consecutively

resource "aws_cloudwatch_metric_alarm" "sast_dlq_alarm" {
  alarm_name          = "${var.project_name}-sast-dlq-not-empty"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "ApproximateNumberOfMessagesVisible"
  namespace           = "AWS/SQS"
  period              = 60
  statistic           = "Sum"
  threshold           = 0
  alarm_description   = "SAST scan failed 3 times — check CloudWatch logs"
  alarm_actions       = [aws_sns_topic.alerts.arn]

  dimensions = {
    QueueName = aws_sqs_queue.sast_dlq.name
  }
}

resource "aws_cloudwatch_metric_alarm" "pentest_dlq_alarm" {
  alarm_name          = "${var.project_name}-pentest-dlq-not-empty"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "ApproximateNumberOfMessagesVisible"
  namespace           = "AWS/SQS"
  period              = 60
  statistic           = "Sum"
  threshold           = 0
  alarm_description   = "Pentest scan failed 3 times — check CloudWatch logs"
  alarm_actions       = [aws_sns_topic.alerts.arn]

  dimensions = {
    QueueName = aws_sqs_queue.pentest_dlq.name
  }
}
