variable "app_name" {
  type = string
}

variable "environment" {
  type = string
}

# ── Access logging bucket ──────────────────────────────────────────────────────
# Receives S3 server-access logs from the files bucket.
# Logging on this bucket itself is intentionally disabled to avoid a circular
# dependency (a logging bucket cannot log to itself).
#tfsec:ignore:aws-s3-enable-bucket-logging
#tfsec:ignore:aws-s3-encryption-customer-key
#tfsec:ignore:aws-s3-enable-versioning
resource "aws_s3_bucket" "logs" {
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

# AES256 (AWS-managed SSE) is acceptable here; a CMK can be added later.
#tfsec:ignore:aws-s3-encryption-customer-key
resource "aws_s3_bucket_server_side_encryption_configuration" "logs" {
  bucket = aws_s3_bucket.logs.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# ── Files bucket ───────────────────────────────────────────────────────────────
# tfsec evaluates the CMK check at the aws_s3_bucket level in addition to
# the SSE configuration resource, so both require the ignore annotation.
#tfsec:ignore:aws-s3-encryption-customer-key
resource "aws_s3_bucket" "files" {
  bucket = "${var.app_name}-files-${var.environment}"
  tags   = { Name = "${var.app_name}-files-${var.environment}" }
}

# AES256 (AWS-managed SSE) is used here. A customer-managed KMS key can be
# introduced later if compliance requirements demand it.
#tfsec:ignore:aws-s3-encryption-customer-key
resource "aws_s3_bucket_server_side_encryption_configuration" "files" {
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
