data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

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
}
