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

resource "aws_db_subnet_group" "main" {
  name       = "${var.app_name}-${var.environment}-db-subnet"
  subnet_ids = var.subnet_ids
}

resource "aws_kms_key" "rds_pi" {
  description             = "KMS key for RDS Performance Insights"
  deletion_window_in_days = 10
  enable_key_rotation     = true
}

#tfsec:ignore:aws-rds-encryption-customer-key
resource "aws_db_instance" "postgres" {
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

  # Protection & recovery
  deletion_protection     = true
  backup_retention_period = 7

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
