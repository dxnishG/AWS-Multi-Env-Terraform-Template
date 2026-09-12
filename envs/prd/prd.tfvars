# ==============================================================================
# PRD — Production Environment
# Multi-AZ web and app tiers, larger instances, NAT Gateway, no force-destroy on S3.
# ==============================================================================

environment = "prd"
aws_region  = "ap-southeast-1"
name_prefix = "myapp"

vpc_cidr           = "10.2.0.0/16"
enable_nat_gateway = true

public_subnet_configs = {
  "web-1a" = { cidr_block = "10.2.1.0/24", availability_zone = "ap-southeast-1a" }
  "web-1b" = { cidr_block = "10.2.2.0/24", availability_zone = "ap-southeast-1b" }
}

private_subnet_configs = {
  "app-1a" = { cidr_block = "10.2.10.0/24", availability_zone = "ap-southeast-1a" }
  "app-1b" = { cidr_block = "10.2.20.0/24", availability_zone = "ap-southeast-1b" }
}

web_sg_ingress_rules = {
  http  = { from_port = 80, to_port = 80, protocol = "tcp", cidr_blocks = ["0.0.0.0/0"], description = "HTTP" }
  https = { from_port = 443, to_port = 443, protocol = "tcp", cidr_blocks = ["0.0.0.0/0"], description = "HTTPS" }
}

ec2_instances = {
  "web-1" = {
    instance_type = "t3.medium"
    subnet_key    = "web-1a"
    role          = "web"
    volume_size   = 50
    volume_type   = "gp3"
  }
  "web-2" = {
    instance_type = "t3.medium"
    subnet_key    = "web-1b"
    role          = "web"
    volume_size   = 50
    volume_type   = "gp3"
  }
}

s3_buckets = {
  "assets" = {
    purpose           = "Static application assets"
    enable_versioning = true
    force_destroy     = false
  }
  "backups" = {
    purpose           = "Application backups"
    enable_versioning = true
    force_destroy     = false
  }
}

tags = {
  Project     = "MyApp"
  Environment = "prd"
  ManagedBy   = "Terraform"
  CostCenter  = "Core-Prod"
}
