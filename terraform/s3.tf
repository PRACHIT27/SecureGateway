# ── S3 REPORTS BUCKET ────────────────────────────────────────────

resource "aws_s3_bucket" "reports" {
  bucket        = "${var.project_name}-reports-${data.aws_caller_identity.current.account_id}"
  force_destroy = true

  tags = { Name = "Scan Reports" }
}

# Block all public access — reports served via presigned URLs only
resource "aws_s3_bucket_public_access_block" "reports" {
  bucket                  = aws_s3_bucket.reports.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Lifecycle — auto-delete reports after retention period
resource "aws_s3_bucket_lifecycle_configuration" "reports" {
  bucket = aws_s3_bucket.reports.id

  rule {
  id     = "expire-old-reports"
  status = "Enabled"

  filter {} 

  expiration {
    days = var.report_retention_days
  }

  noncurrent_version_expiration {
    noncurrent_days = 1
  }
}
}

# Versioning off — reports are write-once, no need for versions
resource "aws_s3_bucket_versioning" "reports" {
  bucket = aws_s3_bucket.reports.id

  versioning_configuration {
    status = "Disabled"
  }
}
