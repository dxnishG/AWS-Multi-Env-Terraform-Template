# Supply aws_account_id, ami_id, certificate_arn, and alarm_topic_arn
# as Terraform variables in this environment's HCP Terraform workspace.
# AMI must contain the tested application and expose /health on port 8080.
environment = "prd"
aws_region  = "ap-southeast-1"
name_prefix = "myapp"
vpc_cidr    = "10.2.0.0/16"
public_subnet_configs = {
  web-1a = { cidr_block = "10.2.1.0/24", availability_zone = "ap-southeast-1a" }
  web-1b = { cidr_block = "10.2.2.0/24", availability_zone = "ap-southeast-1b" }
}
private_subnet_configs = {
  app-1a = { cidr_block = "10.2.10.0/24", availability_zone = "ap-southeast-1a" }
  app-1b = { cidr_block = "10.2.20.0/24", availability_zone = "ap-southeast-1b" }
}
instance_type              = "t3.micro"
min_size                   = 2
max_size                   = 4
app_port                   = 8080
health_check_path          = "/health"
enable_deletion_protection = false
s3_buckets = {
  assets  = { purpose = "Application assets" }
  backups = { purpose = "Application exports" }
}
tags = {
  Project    = "MyApp"
  CostCenter = "Core-Prod"
}
