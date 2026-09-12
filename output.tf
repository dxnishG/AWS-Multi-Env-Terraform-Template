output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.this.id
}

output "public_subnet_ids" {
  description = "Map of public subnet IDs keyed by logical name"
  value       = { for k, v in aws_subnet.public : k => v.id }
}

output "private_subnet_ids" {
  description = "Map of private subnet IDs keyed by logical name"
  value       = { for k, v in aws_subnet.private : k => v.id }
}

output "web_security_group_id" {
  description = "ID of the web-facing security group"
  value       = aws_security_group.web.id
}

output "app_security_group_id" {
  description = "ID of the app-tier security group"
  value       = aws_security_group.app.id
}

output "ec2_instance_ids" {
  description = "Map of EC2 instance IDs keyed by logical name"
  value       = { for k, v in aws_instance.this : k => v.id }
}

output "ec2_instance_public_ips" {
  description = "Map of EC2 public IPs keyed by logical name (web-role instances only)"
  value       = { for k, v in aws_instance.this : k => v.public_ip if v.associate_public_ip_address }
}

output "ec2_instance_private_ips" {
  description = "Map of EC2 private IPs keyed by logical name"
  value       = { for k, v in aws_instance.this : k => v.private_ip }
}

output "s3_bucket_names" {
  description = "Map of S3 bucket names keyed by logical name"
  value       = { for k, v in aws_s3_bucket.this : k => v.bucket }
}

output "s3_bucket_arns" {
  description = "Map of S3 bucket ARNs keyed by logical name"
  value       = { for k, v in aws_s3_bucket.this : k => v.arn }
}

output "iam_instance_profile_name" {
  description = "Name of the EC2 IAM instance profile"
  value       = aws_iam_instance_profile.ec2.name
}

output "key_pair_name" {
  description = "Name of the AWS key pair used by EC2 instances"
  value       = var.create_key_pair ? aws_key_pair.this[0].key_name : var.key_name
}

output "nat_gateway_public_ip" {
  description = "Public IP of the NAT Gateway (if enabled)"
  value       = var.enable_nat_gateway ? aws_eip.nat[0].public_ip : null
}