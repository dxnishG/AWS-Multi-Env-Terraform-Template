# ==============================================================================
# main.tf — Single root configuration for a full application-hosting stack.
#
# Resources (all parameterised via variables; none hardcoded):
#   Network  : VPC · Public & Private Subnets · IGW · NAT GW · Route Tables
#   Security : Web SG (public-facing) · App SG (internal, ingress from Web SG)
#   IAM      : EC2 Instance Role + S3 access inline policy + Instance Profile
#   Compute  : SSH Key Pair · EC2 Instances  (for_each over ec2_instances map)
#   Storage  : S3 Buckets  (for_each over s3_buckets map) with encryption,
#              versioning, and public-access block applied per bucket
# ==============================================================================

locals {
  name_prefix = "${var.name_prefix}-${var.environment}"
  key_name    = var.key_name != "" ? var.key_name : "${local.name_prefix}-key"
}

# ── AMI lookup ─────────────────────────────────────────────────────────────────

data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# ==============================================================================
# Network
# ==============================================================================

resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = { Name = "${local.name_prefix}-vpc" }
}

resource "aws_default_security_group" "this" {
  vpc_id = aws_vpc.this.id

  tags = { Name = "${local.name_prefix}-default-sg" }
}

resource "aws_internet_gateway" "this" {
  count  = length(var.public_subnet_configs) > 0 ? 1 : 0
  vpc_id = aws_vpc.this.id

  tags = { Name = "${local.name_prefix}-igw" }
}

# ── Public Subnets ─────────────────────────────────────────────────────────────

resource "aws_subnet" "public" {
  for_each = var.public_subnet_configs

  vpc_id                  = aws_vpc.this.id
  cidr_block              = each.value.cidr_block
  availability_zone       = each.value.availability_zone
  map_public_ip_on_launch = true

  tags = {
    Name = "${local.name_prefix}-public-${each.key}"
    Tier = "public"
  }
}

resource "aws_route_table" "public" {
  count  = length(var.public_subnet_configs) > 0 ? 1 : 0
  vpc_id = aws_vpc.this.id

  tags = { Name = "${local.name_prefix}-public-rt" }
}

resource "aws_route" "public_internet" {
  count                  = length(var.public_subnet_configs) > 0 ? 1 : 0
  route_table_id         = aws_route_table.public[0].id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this[0].id
}

resource "aws_route_table_association" "public" {
  for_each = aws_subnet.public

  subnet_id      = each.value.id
  route_table_id = aws_route_table.public[0].id
}

# ── Private Subnets ────────────────────────────────────────────────────────────

resource "aws_subnet" "private" {
  for_each = var.private_subnet_configs

  vpc_id                  = aws_vpc.this.id
  cidr_block              = each.value.cidr_block
  availability_zone       = each.value.availability_zone
  map_public_ip_on_launch = false

  tags = {
    Name = "${local.name_prefix}-private-${each.key}"
    Tier = "private"
  }
}

resource "aws_eip" "nat" {
  count  = var.enable_nat_gateway && length(var.public_subnet_configs) > 0 ? 1 : 0
  domain = "vpc"

  tags = { Name = "${local.name_prefix}-nat-eip" }
}

resource "aws_nat_gateway" "this" {
  count         = var.enable_nat_gateway && length(var.public_subnet_configs) > 0 ? 1 : 0
  allocation_id = aws_eip.nat[0].id
  subnet_id     = values(aws_subnet.public)[0].id # first available public subnet

  tags = { Name = "${local.name_prefix}-nat-gw" }

  depends_on = [aws_internet_gateway.this]
}

resource "aws_route_table" "private" {
  count  = length(var.private_subnet_configs) > 0 ? 1 : 0
  vpc_id = aws_vpc.this.id

  tags = { Name = "${local.name_prefix}-private-rt" }
}

resource "aws_route" "private_nat" {
  count                  = var.enable_nat_gateway && length(var.private_subnet_configs) > 0 ? 1 : 0
  route_table_id         = aws_route_table.private[0].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.this[0].id
}

resource "aws_route_table_association" "private" {
  for_each = aws_subnet.private

  subnet_id      = each.value.id
  route_table_id = aws_route_table.private[0].id
}

# ==============================================================================
# Security Groups
# ==============================================================================

# ── Web SG — public-facing (HTTP/HTTPS + SSH) ─────────────────────────────────

resource "aws_security_group" "web" {
  name        = "${local.name_prefix}-web-sg"
  description = "Public-facing SG for ${local.name_prefix} web tier"
  vpc_id      = aws_vpc.this.id

  dynamic "ingress" {
    for_each = var.web_sg_ingress_rules
    content {
      description = ingress.value.description
      from_port   = ingress.value.from_port
      to_port     = ingress.value.to_port
      protocol    = ingress.value.protocol
      cidr_blocks = ingress.value.cidr_blocks
    }
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${local.name_prefix}-web-sg" }
}

# ── App SG — private tier, ingress from web SG only ───────────────────────────

resource "aws_security_group" "app" {
  name        = "${local.name_prefix}-app-sg"
  description = "App-tier SG for ${local.name_prefix}; ingress from web SG"
  vpc_id      = aws_vpc.this.id

  ingress {
    description     = "From web tier"
    from_port       = var.app_port
    to_port         = var.app_port
    protocol        = "tcp"
    security_groups = [aws_security_group.web.id]
  }

  dynamic "ingress" {
    for_each = var.app_sg_additional_rules
    content {
      description = ingress.value.description
      from_port   = ingress.value.from_port
      to_port     = ingress.value.to_port
      protocol    = ingress.value.protocol
      cidr_blocks = ingress.value.cidr_blocks
    }
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${local.name_prefix}-app-sg" }
}

# ==============================================================================
# IAM — EC2 instance profile with S3 access
# ==============================================================================

data "aws_iam_policy_document" "ec2_assume_role" {
  statement {
    sid     = "EC2AssumeRole"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ec2" {
  name               = "${local.name_prefix}-ec2-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json

  tags = { Name = "${local.name_prefix}-ec2-role" }
}

data "aws_iam_policy_document" "s3_access" {
  # Only create this document when there are S3 buckets to grant access to
  count = length(var.s3_buckets) > 0 ? 1 : 0

  statement {
    sid    = "S3BucketAccess"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:ListBucket",
    ]
    resources = concat(
      [for b in aws_s3_bucket.this : b.arn],
      [for b in aws_s3_bucket.this : "${b.arn}/*"],
    )
  }
}

resource "aws_iam_role_policy" "s3_access" {
  count  = length(var.s3_buckets) > 0 ? 1 : 0
  name   = "${local.name_prefix}-s3-access"
  role   = aws_iam_role.ec2.id
  policy = data.aws_iam_policy_document.s3_access[0].json
}

# SSM access so instances can be managed without SSH
resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.ec2.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ec2" {
  name = "${local.name_prefix}-instance-profile"
  role = aws_iam_role.ec2.name
}

# ==============================================================================
# Compute — Key Pair & EC2 Instances
# ==============================================================================

resource "tls_private_key" "ssh" {
  count     = var.create_key_pair ? 1 : 0
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "this" {
  count      = var.create_key_pair ? 1 : 0
  key_name   = local.key_name
  public_key = tls_private_key.ssh[0].public_key_openssh

  tags = { Name = local.key_name }
}

resource "aws_instance" "this" {
  for_each = var.ec2_instances

  ami           = var.ami_id != "" ? var.ami_id : data.aws_ami.amazon_linux_2023.id
  instance_type = each.value.instance_type

  # Route web-role instances to public subnets, app-role to private
  subnet_id = (
    each.value.role == "web"
    ? aws_subnet.public[each.value.subnet_key].id
    : aws_subnet.private[each.value.subnet_key].id
  )

  vpc_security_group_ids = (
    each.value.role == "web"
    ? [aws_security_group.web.id]
    : [aws_security_group.app.id]
  )

  key_name             = var.create_key_pair ? aws_key_pair.this[0].key_name : (var.key_name != "" ? var.key_name : null)
  iam_instance_profile = aws_iam_instance_profile.ec2.name

  associate_public_ip_address = each.value.role == "web"
  ebs_optimized               = true
  monitoring                  = true

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }

  root_block_device {
    volume_size           = each.value.volume_size
    volume_type           = each.value.volume_type
    delete_on_termination = true
    encrypted             = true

    tags = { Name = "${local.name_prefix}-${each.key}-disk" }
  }

  tags = {
    Name = "${local.name_prefix}-${each.key}"
    Role = each.value.role
  }
}

# ==============================================================================
# Storage — S3 Buckets
# ==============================================================================

resource "aws_s3_bucket" "this" {
  for_each = var.s3_buckets

  bucket        = "${local.name_prefix}-${each.key}"
  force_destroy = each.value.force_destroy

  tags = {
    Name    = "${local.name_prefix}-${each.key}"
    Purpose = each.value.purpose
  }
}

resource "aws_s3_bucket_versioning" "this" {
  for_each = { for k, v in var.s3_buckets : k => v if v.enable_versioning }

  bucket = aws_s3_bucket.this[each.key].id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  for_each = var.s3_buckets

  bucket = aws_s3_bucket.this[each.key].id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = "alias/aws/s3"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "this" {
  for_each = var.s3_buckets

  bucket                  = aws_s3_bucket.this[each.key].id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
