resource "aws_secretsmanager_secret" "github_token" {
  name                    = "${var.project_name}-github-token"
  description             = "GitHub token for posting PR comments and setting status checks"
  recovery_window_in_days = 0
  tags = { Name = "GitHub Token" }
}
