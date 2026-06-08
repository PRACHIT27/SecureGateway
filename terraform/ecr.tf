# ── ECR REPOSITORIES ─────────────────────────────────────────────

resource "aws_ecr_repository" "sast_scanner" {
  name                 = "${var.project_name}/sast-scanner"
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = { Name = "SAST Scanner" }
}

resource "aws_ecr_repository" "pentest_worker" {
  name                 = "${var.project_name}/pentest-worker"
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = { Name = "Pentest Worker" }
}

resource "aws_ecr_repository" "client_scans" {
  name                 = "${var.project_name}/client-scans"
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = false # client images scanned by our SAST tool, not ECR
  }

  tags = { Name = "Client Scans" }
}

# ── LIFECYCLE POLICIES ───────────────────────────────────────────
# Keep only last 10 images per repo — prevents ECR storage buildup

resource "aws_ecr_lifecycle_policy" "sast_scanner" {
  repository = aws_ecr_repository.sast_scanner.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep last 10 images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 10
      }
      action = { type = "expire" }
    }]
  })
}

resource "aws_ecr_lifecycle_policy" "client_scans" {
  repository = aws_ecr_repository.client_scans.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Expire client scan images after 1 day"
      selection = {
        tagStatus     = "tagged"
        tagPrefixList = [""]
        countType     = "sinceImagePushed"
        countUnit     = "days"
        countNumber   = 1
      }
      action = { type = "expire" }
    }]
  })
}
