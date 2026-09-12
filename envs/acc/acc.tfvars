# ==============================================================================
# ACC — Acceptance / Staging Environment
# Mirrors production topology with smaller instance sizes.
# ==============================================================================

environment = "acc"
aws_region  = "ap-southeast-1"
name_prefix = "myapp"

vpc_cidr           = "10.1.0.0/16"
enable_nat_gateway = true

public_subnet_configs = {
  "web-1a" = { cidr_block = "10.1.1.0/24", availability_zone = "ap-southeast-1a" }
  "web-1b" = { cidr_block = "10.1.2.0/24", availability_zone = "ap-southeast-1b" }
}

private_subnet_configs = {
  "app-1a" = { cidr_block = "10.1.10.0/24", availability_zone = "ap-southeast-1a" }
  "app-1b" = { cidr_block = "10.1.20.0/24", availability_zone = "ap-southeast-1b" }
}

web_sg_ingress_rules = {
  http  = { from_port = 80, to_port = 80, protocol = "tcp", cidr_blocks = ["0.0.0.0/0"], description = "HTTP" }
  https = { from_port = 443, to_port = 443, protocol = "tcp", cidr_blocks = ["0.0.0.0/0"], description = "HTTPS" }
}

ec2_instances = {
  "web-1" = {
    instance_type = "t3.small"
    subnet_key    = "web-1a"
    role          = "web"
    volume_size   = 20
    volume_type   = "gp3"
  }
}

s3_buckets = {
  "assets" = {
    purpose           = "Static application assets"
    enable_versioning = true
    force_destroy     = false
  }
}

tags = {
  Project     = "MyApp"
  Environment = "acc"
  ManagedBy   = "Terraform"
}
