# Supply aws_account_id, ami_id, certificate_arn, and alarm_topic_arn
# as Terraform variables in this environment's HCP Terraform workspace.
# AMI must contain the tested application and expose /health on port 8080.
environment = "dev"
aws_region  = "us-east-1"
name_prefix = "myapp"
vpc_cidr    = "10.0.0.0/16"
public_subnet_configs = {
  web-1a = { cidr_block = "10.0.1.0/24", availability_zone = "us-east-1a" }
  web-1b = { cidr_block = "10.0.2.0/24", availability_zone = "us-east-1b" }
}
private_subnet_configs = {
  app-1a = { cidr_block = "10.0.10.0/24", availability_zone = "us-east-1a" }
  app-1b = { cidr_block = "10.0.20.0/24", availability_zone = "us-east-1b" }
}
instance_type     = "t3.small"
min_size          = 2
max_size          = 4
app_port          = 8080
health_check_path = "/health"
s3_buckets = {
  assets  = { purpose = "Application assets" }
  backups = { purpose = "Application exports; EC2 snapshots are stored in AWS Backup" }
}
tags = {
  Project    = "MyApp"
  CostCenter = "Engineering"
}
