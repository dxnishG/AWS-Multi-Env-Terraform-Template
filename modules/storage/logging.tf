resource "aws_s3_bucket" "audit" {
  # checkov:skip=CKV_AWS_18:Terminal log sink; recursive server access logging is intentionally avoided.
  # checkov:skip=CKV_AWS_145:S3 server access log delivery requires SSE-S3.
  # checkov:skip=CKV_AWS_144:Regional log archive; organization-wide replication is a separate policy.
  # checkov:skip=CKV2_AWS_62:Passive audit archive has no object-event consumer.
  bucket        = "${var.name}-s3-logs-${data.aws_caller_identity.current.account_id}-${data.aws_region.current.name}"
  force_destroy = false
}
resource "aws_s3_bucket_public_access_block" "audit" {
  bucket                  = aws_s3_bucket.audit.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
resource "aws_s3_bucket_server_side_encryption_configuration" "audit" {
  bucket = aws_s3_bucket.audit.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}
resource "aws_s3_bucket_versioning" "audit" {
  bucket = aws_s3_bucket.audit.id
  versioning_configuration {
    status = "Enabled"
  }
}
resource "aws_s3_bucket_lifecycle_configuration" "audit" {
  bucket = aws_s3_bucket.audit.id
  rule {
    id     = "retention"
    status = "Enabled"
    filter {}
    expiration {
      days = 365
    }
    noncurrent_version_expiration {
      noncurrent_days = 30
    }
    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
  depends_on = [aws_s3_bucket_versioning.audit]
}
data "aws_iam_policy_document" "audit" {
  statement {
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.audit.arn}/*"]
    principals {
      type        = "Service"
      identifiers = ["logging.s3.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = ["arn:aws:s3:::${var.name}-*"]
    }
  }
  statement {
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [aws_s3_bucket.audit.arn, "${aws_s3_bucket.audit.arn}/*"]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}
resource "aws_s3_bucket_policy" "audit" {
  bucket = aws_s3_bucket.audit.id
  policy = data.aws_iam_policy_document.audit.json
}
resource "aws_s3_bucket_logging" "this" {
  for_each      = var.buckets
  bucket        = aws_s3_bucket.this[each.key].id
  target_bucket = aws_s3_bucket.audit.id
  target_prefix = "${each.key}/"
  depends_on    = [aws_s3_bucket_policy.audit]
}
