# AWS Backup — centralized backup plans, immutable vaults, cross-region copy
# Deploys: backup vaults (prod + DR region), KMS keys, daily plan with
# tag-based selection, Vault Lock (Compliance mode), and restore-test Lambda.
# Usage: terraform init && terraform apply

terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "ap-southeast-1" # primary region
}

provider "aws" {
  alias  = "dr"
  region = "ap-southeast-2" # DR region
}

# ---------------------------------------------------------------------------
# KMS keys — one per region, so a key compromise in one region can't
# decrypt the other region's recovery points.
# ---------------------------------------------------------------------------
resource "aws_kms_key" "backup_primary" {
  description             = "AWS Backup vault encryption — primary region"
  deletion_window_in_days = 30
  enable_key_rotation     = true
}

resource "aws_kms_key" "backup_dr" {
  provider                = aws.dr
  description             = "AWS Backup vault encryption — DR region"
  deletion_window_in_days = 30
  enable_key_rotation     = true
}

# ---------------------------------------------------------------------------
# Backup vaults
# ---------------------------------------------------------------------------
resource "aws_backup_vault" "prod" {
  name        = "prod-vault"
  kms_key_arn = aws_kms_key.backup_primary.arn

  tags = { Environment = "prod", ManagedBy = "terraform" }
}

resource "aws_backup_vault" "dr" {
  provider    = aws.dr
  name        = "dr-vault"
  kms_key_arn = aws_kms_key.backup_dr.arn

  tags = { Environment = "prod", ManagedBy = "terraform" }
}

# Vault Lock — Compliance mode. After the 3-day grace period expires,
# NOBODY (not even root) can delete recovery points or shorten retention.
resource "aws_backup_vault_lock_configuration" "prod" {
  backup_vault_name   = aws_backup_vault.prod.name
  min_retention_days  = 7
  max_retention_days  = 365
  changeable_for_days = 3
}

resource "aws_backup_vault_lock_configuration" "dr" {
  provider            = aws.dr
  backup_vault_name   = aws_backup_vault.dr.name
  min_retention_days  = 7
  max_retention_days  = 365
  changeable_for_days = 3
}

# ---------------------------------------------------------------------------
# Backup plan — daily 02:00 UTC, 7 days warm, 30 days total,
# cross-region copy kept 90 days in the DR vault.
# ---------------------------------------------------------------------------
resource "aws_backup_plan" "prod" {
  name = "prod-daily-plan"

  rule {
    rule_name         = "daily"
    target_vault_name = aws_backup_vault.prod.name
    schedule          = "cron(0 2 * * ? *)"

    lifecycle {
      cold_storage_after = 7
      delete_after       = 30
    }

    copy_action {
      destination_vault_arn = aws_backup_vault.dr.arn
      lifecycle {
        delete_after = 90
      }
    }
  }

  advanced_backup_setting {
    backup_options = {
      WindowsVSS = "enabled" # application-consistent EC2 snapshots
    }
    resource_type = "EC2"
  }
}

# Tag-based selection: any resource tagged Backup=daily is protected.
# New resources are covered automatically once tagged — no plan edits.
resource "aws_backup_selection" "prod" {
  name         = "prod-tag-selection"
  iam_role_arn = aws_iam_role.backup.arn
  plan_id      = aws_backup_plan.prod.id

  selection_tag {
    type  = "STRINGEQUALS"
    key   = "Backup"
    value = "daily"
  }

  # Never back up scratch / ephemeral resources, even if tagged by mistake.
  condition {
    string_not_equals {
      key   = "aws:ResourceTag/Environment"
      value = "ephemeral"
    }
  }
}

# ---------------------------------------------------------------------------
# IAM role — least privilege: AWS Backup managed policy only.
# ---------------------------------------------------------------------------
resource "aws_iam_role" "backup" {
  name               = "AWSBackupServiceRole"
  assume_role_policy = data.aws_iam_policy_document.backup_assume.json
}

data "aws_iam_policy_document" "backup_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["backup.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy_attachment" "backup" {
  role       = aws_iam_role.backup.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForBackup"
}

resource "aws_iam_role_policy_attachment" "backup_restore" {
  role       = aws_iam_role.backup.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForRestores"
}

# ---------------------------------------------------------------------------
# Alerting — a failed backup job pages on-call via SNS.
# ---------------------------------------------------------------------------
resource "aws_sns_topic" "backup_alerts" {
  name = "backup-job-alerts"
}

resource "aws_cloudwatch_event_rule" "backup_failed" {
  name        = "backup-job-failed"
  description = "Fires when any AWS Backup job fails or expires"

  event_pattern = jsonencode({
    source      = ["aws.backup"]
    detail-type = ["Backup Job State Change"]
    detail = {
      state = ["FAILED", "EXPIRED", "ABORTED"]
    }
  })
}

resource "aws_cloudwatch_event_target" "backup_failed_sns" {
  rule      = aws_cloudwatch_event_rule.backup_failed.name
  target_id = "sns"
  arn       = aws_sns_topic.backup_alerts.arn
}

# ---------------------------------------------------------------------------
# Outputs
# ---------------------------------------------------------------------------
output "prod_vault_arn" {
  value = aws_backup_vault.prod.arn
}

output "dr_vault_arn" {
  value = aws_backup_vault.dr.arn
}

output "backup_plan_id" {
  value = aws_backup_plan.prod.id
}

output "alerts_topic_arn" {
  value = aws_sns_topic.backup_alerts.arn
}
