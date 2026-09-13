mock_provider "aws" {
  mock_data "aws_iam_policy_document" {
    defaults = { json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}" }
  }
  mock_data "aws_caller_identity" {
    defaults = { account_id = "123456789012" }
  }
  mock_data "aws_region" {
    defaults = { name = "us-east-1" }
  }
  mock_data "aws_ec2_instance_type" {
    defaults = { supported_architectures = ["arm64"] }
  }
  mock_data "aws_ami" {
    defaults = { architecture = "arm64" }
  }
}
run "network_az_isolation" {
  command = plan
  module { source = "./modules/network" }
  variables {
    name     = "testapp-prd"
    vpc_cidr = "10.2.0.0/16"
    public_subnets = {
      a = { cidr_block = "10.2.1.0/24", availability_zone = "us-east-1a" }
      b = { cidr_block = "10.2.2.0/24", availability_zone = "us-east-1b" }
    }
    private_subnets = {
      a = { cidr_block = "10.2.10.0/24", availability_zone = "us-east-1a" }
      b = { cidr_block = "10.2.20.0/24", availability_zone = "us-east-1b" }
    }
  }
  assert {
    condition     = length(aws_nat_gateway.this) == 2 && length(aws_route_table.private) == 2
    error_message = "Each AZ must have its own NAT and private route table."
  }
  assert {
    condition     = alltrue([for s in aws_subnet.public : !s.map_public_ip_on_launch]) && alltrue([for s in aws_subnet.private : !s.map_public_ip_on_launch])
    error_message = "Subnets must not automatically expose instances."
  }
}
run "private_service_contract" {
  command = plan
  module { source = "./modules/service" }
  variables {
    name               = "testapp-prd"
    vpc_id             = "vpc-12345678"
    public_subnet_ids  = ["subnet-11111111", "subnet-22222222"]
    private_subnet_ids = ["subnet-33333333", "subnet-44444444"]
    ami_id             = "ami-0123456789abcdef0"
    certificate_arn    = "arn:aws:acm:us-east-1:123456789012:certificate/test"
    instance_type      = "t4g.small"
    app_port           = 8080
    health_check_path  = "/health"
    min_size           = 2
    max_size           = 4
    alarm_topic_arn    = "arn:aws:sns:us-east-1:123456789012:operations"
    bucket_arns        = {}
    bucket_kms_key_arn = "arn:aws:kms:us-east-1:123456789012:key/test"
    tags               = {}
  }
  assert {
    condition     = aws_lb_listener.https.protocol == "HTTPS" && aws_lb.this.enable_deletion_protection
    error_message = "Production entry point must use TLS and enable deletion protection."
  }
  assert {
    condition     = one(aws_launch_template.this.network_interfaces).associate_public_ip_address == "false" && aws_launch_template.this.metadata_options[0].http_tokens == "required"
    error_message = "Application instances must be private and require IMDSv2."
  }
  assert {
    condition     = aws_autoscaling_group.this.health_check_type == "ELB" && aws_autoscaling_group.this.min_size >= 2
    error_message = "Production needs redundant capacity and application health replacement."
  }
}
run "storage_retention" {
  command = plan
  module { source = "./modules/storage" }
  variables {
    name    = "testapp-prd"
    buckets = { assets = { purpose = "Assets" } }
  }
  assert {
    condition     = aws_s3_bucket.this["assets"].force_destroy && aws_s3_bucket_versioning.this["assets"].versioning_configuration[0].status == "Enabled"
    error_message = "Data buckets must retain versions."
  }
}
