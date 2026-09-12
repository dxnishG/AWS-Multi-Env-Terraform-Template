variable "environment" {
  description = "Deployment environment (dev / acc / prd)"
  type        = string

  validation {
    condition     = contains(["dev", "acc", "prd"], var.environment)
    error_message = "environment must be one of: dev, acc, prd."
  }
}

variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "us-east-1"
}

variable "name_prefix" {
  description = "Short identifier prepended to every resource name"
  type        = string
  default     = "app"
}

# ==============================================================================
# Network
# ==============================================================================

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
}

variable "public_subnet_configs" {
  description = "Map of public subnets. Key = logical name used in other references."
  type = map(object({
    cidr_block        = string
    availability_zone = string
  }))
  default = {}
}

variable "private_subnet_configs" {
  description = "Map of private subnets. Key = logical name used in EC2 subnet_key."
  type = map(object({
    cidr_block        = string
    availability_zone = string
  }))
  default = {}
}

variable "enable_nat_gateway" {
  description = "Provision a NAT Gateway so private instances can reach the internet"
  type        = bool
  default     = false
}

# ==============================================================================
# Security Groups
# ==============================================================================

variable "web_sg_ingress_rules" {
  description = "Ingress rules for the public-facing (web) security group, keyed by rule name."
  type = map(object({
    from_port   = number
    to_port     = number
    protocol    = string
    cidr_blocks = list(string)
    description = optional(string, "")
  }))
  default = {}
}

variable "app_port" {
  description = "Port the application tier listens on (used for web→app SG ingress)"
  type        = number
  default     = 8080
}

variable "app_sg_additional_rules" {
  description = "Extra ingress rules for the app-tier security group (e.g. management SSH), keyed by rule name."
  type = map(object({
    from_port   = number
    to_port     = number
    protocol    = string
    cidr_blocks = list(string)
    description = optional(string, "")
  }))
  default = {}
}

# ==============================================================================
# Compute — EC2
# ==============================================================================

variable "ami_id" {
  description = "Custom AMI ID. Leave empty to use the latest Amazon Linux 2023."
  type        = string
  default     = ""
}

variable "create_key_pair" {
  description = "Generate a new TLS key pair and register it in AWS"
  type        = bool
  default     = true
}

variable "key_name" {
  description = "Key pair name. Used as the name for the generated key when create_key_pair = true; used as-is when false."
  type        = string
  default     = ""
}

variable "ec2_instances" {
  description = <<-EOT
    Map of EC2 instances to create, keyed by logical name.
      role       : "web" → placed in public subnet + web SG; "app" → private subnet + app SG.
      subnet_key : must match a key in public_subnet_configs (web) or private_subnet_configs (app).
  EOT
  type = map(object({
    instance_type = string
    role          = string
    subnet_key    = string
    volume_size   = optional(number, 20)
    volume_type   = optional(string, "gp3")
  }))
  default = {}

  validation {
    condition     = alltrue([for inst in values(var.ec2_instances) : contains(["web", "app"], inst.role)])
    error_message = "Each ec2_instances entry must have role = \"web\" or \"app\"."
  }
}

# ==============================================================================
# Storage — S3
# ==============================================================================

variable "s3_buckets" {
  description = "Map of S3 buckets to create, keyed by logical name (becomes part of the bucket name)."
  type = map(object({
    purpose           = string
    enable_versioning = bool
    force_destroy     = optional(bool, true)
  }))
  default = {}
}

# ==============================================================================
# Tags
# ==============================================================================

variable "tags" {
  description = "Tags applied to every resource via the provider default_tags block"
  type        = map(string)
  default     = {}
}