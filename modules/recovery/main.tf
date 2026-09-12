resource "aws_backup_vault" "this" {
  kms_key_arn   = aws_kms_key.this.arn
  name          = "${var.name}-recovery"
  force_destroy = false
  lifecycle {
    prevent_destroy = true
  }
}
resource "aws_backup_plan" "this" {
  name = "${var.name}-daily"
  rule {
    rule_name         = "daily"
    target_vault_name = aws_backup_vault.this.name
    schedule          = "cron(0 3 * * ? *)"
    start_window      = 60
    completion_window = 180
    lifecycle {
      delete_after = 35
    }
  }
}
data "aws_iam_policy_document" "trust" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["backup.amazonaws.com"]
    }
  }
}
resource "aws_iam_role" "this" {
  name               = "${var.name}-backup"
  assume_role_policy = data.aws_iam_policy_document.trust.json
}
resource "aws_iam_role_policy_attachment" "this" {
  role       = aws_iam_role.this.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForBackup"
}
data "aws_region" "current" {}
data "aws_caller_identity" "current" {}
resource "aws_backup_selection" "this" {
  name         = "${var.name}-instances"
  iam_role_arn = aws_iam_role.this.arn
  plan_id      = aws_backup_plan.this.id
  resources    = ["arn:aws:ec2:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:instance/*"]
  condition {
    string_equals {
      key   = "aws:ResourceTag/Backup"
      value = var.name
    }
  }
  depends_on = [aws_iam_role_policy_attachment.this]
}
resource "aws_cloudwatch_metric_alarm" "failed" {
  alarm_name          = "${var.name}-backup-failed"
  namespace           = "AWS/Backup"
  metric_name         = "NumberOfBackupJobsFailed"
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  comparison_operator = "GreaterThanThreshold"
  threshold           = 0
  treat_missing_data  = "notBreaching"
  dimensions          = { BackupVaultName = aws_backup_vault.this.name }
  alarm_actions       = [var.alarm_topic_arn]
}
