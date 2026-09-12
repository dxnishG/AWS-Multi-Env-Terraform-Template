data "aws_caller_identity" "current" {}

data "aws_iam_policy_document" "key" {
  # checkov:skip=CKV_AWS_109:KMS resource policy delegates administration to this account; not an identity policy.
  # checkov:skip=CKV_AWS_111:In a KMS key policy, Resource * means only the attached key.
  # checkov:skip=CKV_AWS_356:KMS key policies require Resource *; account principal and log encryption context constrain access.
  statement {
    sid       = "EnableAccountIAM"
    actions   = ["kms:*"]
    resources = ["*"]
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
  }
  statement {
    sid       = "CloudWatchLogs"
    actions   = ["kms:Encrypt", "kms:Decrypt", "kms:ReEncrypt*", "kms:GenerateDataKey*", "kms:DescribeKey"]
    resources = ["*"]
    principals {
      type        = "Service"
      identifiers = ["logs.${data.aws_region.current.region}.amazonaws.com"]
    }
    condition {
      test     = "ArnEquals"
      variable = "kms:EncryptionContext:aws:logs:arn"
      values   = ["arn:aws:logs:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:log-group:/vpc/${var.name}/flow"]
    }
  }
}
resource "aws_kms_key" "this" {
  description             = "Log encryption for ${var.name}"
  enable_key_rotation     = true
  deletion_window_in_days = 30
  policy                  = data.aws_iam_policy_document.key.json
  lifecycle {
    prevent_destroy = true
  }
}
