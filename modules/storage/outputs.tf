output "bucket_arns" {
  description = "bucket arns produced by this module."
  value       = { for k, b in aws_s3_bucket.this : k => b.arn }
}

output "bucket_names" {
  description = "bucket names produced by this module."
  value       = { for k, b in aws_s3_bucket.this : k => b.bucket }
}

output "kms_key_arn" {
  description = "kms key arn produced by this module."
  value       = aws_kms_key.this.arn
}
