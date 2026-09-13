variable "environment" {
  description = "Environment name; prd enables production safeguards."
  type        = string
  validation {
    condition     = contains(["dev", "acc", "prd"], var.environment)
    error_message = "Use dev, acc, or prd."
  }
}
variable "aws_region" {
  description = "Deployment region, also the region of the AMI, ACM certificate and SNS topic."
  type        = string
}
variable "aws_account_id" {
  description = "Expected AWS account; prevents deployment into the wrong account."
  type        = string
  validation {
    condition     = can(regex("^[0-9]{12}$", var.aws_account_id))
    error_message = "Provide the intended 12-digit AWS account ID."
  }
}
variable "name_prefix" {
  description = "Short lowercase resource prefix."
  type        = string
  default     = "app"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,15}$", var.name_prefix))
    error_message = "Use 2-16 lowercase letters, digits or hyphens, starting with a letter."
  }
}
variable "vpc_cidr" {
  description = "IPv4 VPC CIDR."
  type        = string
  validation {
    condition     = can(cidrnetmask(var.vpc_cidr))
    error_message = "Provide an IPv4 CIDR."
  }
}
variable "public_subnet_configs" {
  description = "Public ALB/NAT subnets, one per AZ. Keep existing keys during migration."
  type        = map(object({ cidr_block = string, availability_zone = string }))
  default = {
    web-1a = { cidr_block = "10.0.1.0/24", availability_zone = "us-east-1a" }
    web-1b = { cidr_block = "10.0.2.0/24", availability_zone = "us-east-1b" }
  }
  validation {
    condition     = length(var.public_subnet_configs) >= 2 && length(distinct([for s in var.public_subnet_configs : s.availability_zone])) == length(var.public_subnet_configs)
    error_message = "Provide at least two public subnets in distinct AZs."
  }
}
variable "private_subnet_configs" {
  description = "Private application subnets with a matching public subnet in each AZ."
  type        = map(object({ cidr_block = string, availability_zone = string }))
  default = {
    app-1a = { cidr_block = "10.0.10.0/24", availability_zone = "us-east-1a" }
    app-1b = { cidr_block = "10.0.20.0/24", availability_zone = "us-east-1b" }
  }
  validation {
    condition     = length(var.private_subnet_configs) >= 2 && length(distinct([for s in var.private_subnet_configs : s.availability_zone])) == length(var.private_subnet_configs) && alltrue([for s in var.private_subnet_configs : contains([for p in var.public_subnet_configs : p.availability_zone], s.availability_zone)])
    error_message = "Provide at least two distinct private AZs, each with a public subnet in the same AZ."
  }
}
variable "ami_id" {
  description = "Pinned, tested application AMI with SSM agent and the service listening on app_port. No latest-image fallback."
  type        = string
  validation {
    condition     = can(regex("^ami-([0-9a-f]{8}|[0-9a-f]{17})$", var.ami_id))
    error_message = "Provide a pinned application AMI ID."
  }
}
variable "certificate_arn" {
  description = "Issued ACM certificate in the deployment region for the application hostname."
  type        = string
  validation {
    condition     = can(regex("^arn:aws:acm:${var.aws_region}:${var.aws_account_id}:certificate/", var.certificate_arn))
    error_message = "Provide an ACM certificate ARN in the target account and region."
  }
}
variable "alarm_topic_arn" {
  description = "Existing SNS topic with a confirmed operations subscription in the target region/account."
  type        = string
  validation {
    condition     = can(regex("^arn:aws:sns:${var.aws_region}:${var.aws_account_id}:", var.alarm_topic_arn))
    error_message = "Provide an operations SNS topic ARN in the target account and region."
  }
}
variable "instance_type" {
  description = "ARM64 instance type compatible with the pinned application AMI."
  type        = string
  default     = "t4g.small"
}
variable "app_port" {
  description = "Application HTTP port reachable only from the ALB."
  type        = number
  default     = 8080
  validation {
    condition     = var.app_port >= 1 && var.app_port <= 65535 && floor(var.app_port) == var.app_port
    error_message = "Use an integer TCP port between 1 and 65535."
  }
}
variable "health_check_path" {
  description = "Unauthenticated readiness endpoint returning HTTP 200 only when the application can serve traffic."
  type        = string
  default     = "/health"
  validation {
    condition     = startswith(var.health_check_path, "/")
    error_message = "The health-check path must start with /."
  }
}
variable "min_size" {
  description = "Minimum healthy capacity; production requires at least two instances."
  type        = number
  default     = 2
  validation {
    condition     = var.min_size >= (var.environment == "prd" ? 2 : 1) && floor(var.min_size) == var.min_size
    error_message = "Use positive integer capacity, at least two in production."
  }
}
variable "max_size" {
  description = "Maximum capacity, with room for rolling replacements."
  type        = number
  default     = 4
  validation {
    condition     = var.max_size > var.min_size && floor(var.max_size) == var.max_size
    error_message = "Maximum capacity must be an integer greater than minimum capacity."
  }
}
variable "s3_buckets" {
  description = "Versioned, encrypted data buckets. Destructive deletion is disabled."
  type        = map(object({ purpose = string }))
  default     = { assets = { purpose = "Application assets" } }
}
variable "tags" {
  description = "Additional resource tags."
  type        = map(string)
  default     = {}
}
