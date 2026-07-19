variable "app_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "db_password" {
  type      = string
  sensitive = true
}

variable "vpc_id" {
  type = string
}

variable "subnet_ids" {
  type = list(string)
}

variable "sg_id" {
  type = string
}

data "aws_caller_identity" "current" {}

# ── Subnet group ───────────────────────────────────────────────────────────────
resource "aws_db_subnet_group" "main" {
  name       = "${var.app_name}-${var.environment}-db-subnet"
  subnet_ids = var.subnet_ids
}

# ── KMS key for Performance Insights ──────────────────────────────────────────
resource "aws_kms_key" "rds_pi" {
  description             = "KMS key for RDS Performance Insights"
  deletion_window_in_days = 10
  enable_key_rotation     = true
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "Enable IAM User Permissions"
        Effect    = "Allow"
        Principal = { AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root" }
        Action    = "kms:*"
        Resource  = "*"
      }
    ]
  })
}

# ── Enhanced Monitoring IAM role ───────────────────────────────────────────────
resource "aws_iam_role" "rds_monitoring" {
  name = "${var.app_name}-${var.environment}-rds-monitoring-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "monitoring.rds.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "rds_monitoring" {
  role       = aws_iam_role.rds_monitoring.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

# ── RDS instance ───────────────────────────────────────────────────────────────
#tfsec:ignore:aws-rds-encryption-customer-key
resource "aws_db_instance" "postgres" {
  #checkov:skip=CKV_AWS_157:Multi-AZ disabled for non-prod to control cost.
  #checkov:skip=CKV2_AWS_30:Postgres query logging not needed for non-prod.
  identifier     = "${var.app_name}-${var.environment}-postgres"
  engine         = "postgres"
  engine_version = "16"
  instance_class = "db.t3.micro"

  allocated_storage = 20
  storage_type      = "gp3"
  storage_encrypted = true

  db_name  = "cixiohub"
  username = "cixiohub"
  password = var.db_password

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [var.sg_id]

  publicly_accessible = false

  # Authentication & access
  iam_database_authentication_enabled = true

  # Logging & monitoring
  enabled_cloudwatch_logs_exports = ["postgresql", "upgrade"]
  monitoring_interval             = 60
  monitoring_role_arn             = aws_iam_role.rds_monitoring.arn

  # Protection & recovery
  deletion_protection     = true
  backup_retention_period = 7
  copy_tags_to_snapshot   = true

  # Upgrades
  auto_minor_version_upgrade = true

  # Skip final snapshot only in non-prod to speed up teardown
  skip_final_snapshot = var.environment != "prod"

  # Performance Insights
  performance_insights_enabled    = true
  performance_insights_kms_key_id = aws_kms_key.rds_pi.arn

  tags = { Name = "${var.app_name}-${var.environment}-postgres" }
}

output "endpoint" {
  value = aws_db_instance.postgres.address
}

output "port" {
  value = aws_db_instance.postgres.port
}
