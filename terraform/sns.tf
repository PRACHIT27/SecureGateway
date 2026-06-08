# ── SNS ALERTS TOPIC ─────────────────────────────────────────────
# Used for: DLQ alarms, critical scan findings, Fargate memory alerts

resource "aws_sns_topic" "alerts" {
  name = "${var.project_name}-alerts"
  tags = { Name = "SecureGate Alerts" }
}

# Email subscription — update this to your email before applying
resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = "prachit@example.com" # TODO: replace with your email
}
