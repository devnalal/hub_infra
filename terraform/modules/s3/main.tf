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
#tfsec:ignore:aws-s3-enable-bucket-logging tfsec:ignore:aws-s3-encryption-customer-key
resource "aws_s3_bucket" "logs" {
  #checkov:skip=CKV_AWS_18:Access logging bucket does not require logging to avoid circular dependency
  #checkov:skip=CKV_AWS_145:Access logging bucket encryption uses standard S3-managed AES256 encryption rather than KMS CMK
  #checkov:skip=CKV_AWS_19:Access logging bucket encryption is managed by SSE-S3 (AES256) in a separate resource
  #checkov:skip=CKV_AWS_144:Cross-region replication is not required for logs bucket.
  #checkov:skip=CKV2_AWS_62:Event notifications are not required for logs bucket.
  bucket = "${var.app_name}-access-logs-${var.environment}"
  tags   = { Name = "${var.app_name}-access-logs-${var.environment}" }
}

resource "aws_s3_bucket_versioning" "logs" {
  bucket = aws_s3_bucket.logs.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_public_access_block" "logs" {
  bucket                  = aws_s3_bucket.logs.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "logs" {
  #checkov:skip=CKV_AWS_300:Logs bucket does not use multipart uploads, no abort rule needed.
  bucket = aws_s3_bucket.logs.id

  rule {
    id     = "expire-old-logs"
    status = "Enabled"

    filter {}

    expiration {
      days = 365
    }
  }
}

# AES256 (AWS-managed SSE) is acceptable here; a CMK can be added later.
#tfsec:ignore:aws-s3-encryption-customer-key
resource "aws_s3_bucket_server_side_encryption_configuration" "logs" {
  #checkov:skip=CKV_AWS_145:Access logging bucket encryption uses SSE-S3 (AES256) instead of KMS CMK
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
  #checkov:skip=CKV_AWS_145:Files bucket encryption uses standard S3-managed AES256 encryption rather than KMS CMK
  #checkov:skip=CKV_AWS_19:Files bucket encryption is managed by SSE-S3 (AES256) in a separate resource
  #checkov:skip=CKV_AWS_144:Cross-region replication is not required for files bucket.
  #checkov:skip=CKV2_AWS_62:Event notifications are not required for files bucket.
  bucket = "${var.app_name}-files-${var.environment}"
  tags   = { Name = "${var.app_name}-files-${var.environment}" }
}

# AES256 (AWS-managed SSE) is used here. A customer-managed KMS key can be
# introduced later if compliance requirements demand it.
#tfsec:ignore:aws-s3-encryption-customer-key
resource "aws_s3_bucket_server_side_encryption_configuration" "files" {
  #checkov:skip=CKV_AWS_145:Files bucket encryption uses SSE-S3 (AES256) instead of KMS CMK
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

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
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
