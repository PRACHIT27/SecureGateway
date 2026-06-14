# ── SNS ALERTS TOPIC ─────────────────────────────────────────────
# Used for: DLQ alarms, critical scan findings, Fargate memory alerts

resource "aws_sns_topic" "alerts" {
  name = "${var.project_name}-alerts"
  tags = { Name = "SecureGate Alerts" }
}

resource "aws_sns_topic_subscription" "email_parishi" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = "shah.parish@northeastern.edu"
}

resource "aws_sns_topic_subscription" "email_prachit" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = "tupe.p@northeastern.edu"
}
