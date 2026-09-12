# ==============================================================================
# DEV — Application Hosting Infrastructure
#
# Deploys: VPC · Public & Private Subnets (2 AZs) · IGW
#          Web SG · App SG · IAM Instance Profile
#          2 Web EC2 Instances (public) · 2 App EC2 Instances (private)
#          Assets S3 Bucket · Backups S3 Bucket
# ==============================================================================

environment = "dev"
aws_region  = "us-east-1"
name_prefix = "myapp"

# ------------------------------------------------------------------------------
# Network
# ------------------------------------------------------------------------------
vpc_cidr           = "10.0.0.0/16"
enable_nat_gateway = false # Dev: save cost, web tier handles external access

public_subnet_configs = {
  "web-1a" = { cidr_block = "10.0.1.0/24", availability_zone = "us-east-1a" }
  "web-1b" = { cidr_block = "10.0.2.0/24", availability_zone = "us-east-1b" }
}

private_subnet_configs = {
  "app-1a" = { cidr_block = "10.0.10.0/24", availability_zone = "us-east-1a" }
  "app-1b" = { cidr_block = "10.0.20.0/24", availability_zone = "us-east-1b" }
}

# ------------------------------------------------------------------------------
# Security Groups & Rules
# ------------------------------------------------------------------------------
web_sg_ingress_rules = {
  http  = { from_port = 80, to_port = 80, protocol = "tcp", cidr_blocks = ["0.0.0.0/0"], description = "HTTP from Internet" }
  https = { from_port = 443, to_port = 443, protocol = "tcp", cidr_blocks = ["0.0.0.0/0"], description = "HTTPS from Internet" }
  ssh   = { from_port = 22, to_port = 22, protocol = "tcp", cidr_blocks = ["10.0.0.0/16"], description = "SSH from VPC" }
}

app_sg_additional_rules = {
  ssh = { from_port = 22, to_port = 22, protocol = "tcp", cidr_blocks = ["10.0.0.0/16"], description = "SSH from VPC" }
}

# ------------------------------------------------------------------------------
# Compute — EC2 Instances
# ------------------------------------------------------------------------------
ec2_instances = {
  "web-1" = {
    instance_type = "t3.micro"
    subnet_key    = "web-1a"
    role          = "web"
    volume_size   = 20
    volume_type   = "gp3"
  }
  "web-2" = {
    instance_type = "t3.micro"
    subnet_key    = "web-1b"
    role          = "web"
    volume_size   = 20
    volume_type   = "gp3"
  }
  "app-1" = {
    instance_type = "t3.micro"
    subnet_key    = "app-1a"
    role          = "app"
    volume_size   = 30
    volume_type   = "gp3"
  }
  "app-2" = {
    instance_type = "t3.micro"
    subnet_key    = "app-1b"
    role          = "app"
    volume_size   = 30
    volume_type   = "gp3"
  }
}

# ------------------------------------------------------------------------------
# Storage — S3 Buckets
# ------------------------------------------------------------------------------
s3_buckets = {
  "assets" = {
    purpose           = "Static application assets"
    enable_versioning = true
    force_destroy     = true # Dev: allow easy teardown
  }
  "backups" = {
    purpose           = "Application backups"
    enable_versioning = false
    force_destroy     = true
  }
}

# ------------------------------------------------------------------------------
# Tags
# ------------------------------------------------------------------------------
tags = {
  Project     = "MyApp"
  Environment = "dev"
  ManagedBy   = "Terraform"
  CostCenter  = "Engineering-Dev"
}
