variable "app_name" {
  type = string
}

variable "environment" {
  type = string
}

# ── Access logging bucket ──────────────────────────────────────────────────────
# Receives S3 server-access logs from the files bucket.
# Logging is intentionally disabled on this bucket itself to avoid a circular
# dependency; the logging bucket only stores access logs from other buckets.
# tfsec:ignore:aws-s3-enable-bucket-logging

resource "aws_s3_bucket" "logs" {
  # tfsec:ignore:aws-s3-enable-bucket-logging
  bucket = "${var.app_name}-access-logs-${var.environment}"
  tags   = { Name = "${var.app_name}-access-logs-${var.environment}" }
}

resource "aws_s3_bucket_public_access_block" "logs" {
  bucket                  = aws_s3_bucket.logs.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "logs" {
  # tfsec:ignore:aws-s3-encryption-customer-key
  bucket = aws_s3_bucket.logs.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# ── Files bucket ───────────────────────────────────────────────────────────────

resource "aws_s3_bucket" "files" {
  bucket = "${var.app_name}-files-${var.environment}"
  tags   = { Name = "${var.app_name}-files-${var.environment}" }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "files" {
  # AES256 (AWS-managed SSE) is used here. A customer-managed KMS key can be
  # introduced later if compliance requirements demand it.
  # tfsec:ignore:aws-s3-encryption-customer-key
  bucket = aws_s3_bucket.files.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_versioning" "files" {
  bucket = aws_s3_bucket.files.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_logging" "files" {
  bucket        = aws_s3_bucket.files.id
  target_bucket = aws_s3_bucket.logs.id
  target_prefix = "s3-access-logs/"
}

resource "aws_s3_bucket_lifecycle_configuration" "files" {
  bucket = aws_s3_bucket.files.id

  rule {
    id     = "archive-old-files"
    status = "Enabled"

    transition {
      days          = 90
      storage_class = "GLACIER"
    }

    filter { prefix = "uploads/" }
  }
}

resource "aws_s3_bucket_public_access_block" "files" {
  bucket                  = aws_s3_bucket.files.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

output "bucket_name" {
  value = aws_s3_bucket.files.bucket
}

output "bucket_arn" {
  value = aws_s3_bucket.files.arn
}
