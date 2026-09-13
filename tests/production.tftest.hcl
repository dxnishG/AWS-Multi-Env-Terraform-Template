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
}

variables {
  environment     = "prd"
  aws_region      = "us-east-1"
  aws_account_id  = "123456789012"
  name_prefix     = "testapp"
  vpc_cidr        = "10.2.0.0/16"
  ami_id          = "ami-0123456789abcdef0"
  certificate_arn = "arn:aws:acm:us-east-1:123456789012:certificate/test"
  alarm_topic_arn = "arn:aws:sns:us-east-1:123456789012:operations"
  public_subnet_configs = {
    a = { cidr_block = "10.2.1.0/24", availability_zone = "us-east-1a" }
    b = { cidr_block = "10.2.2.0/24", availability_zone = "us-east-1b" }
  }
  private_subnet_configs = {
    a = { cidr_block = "10.2.10.0/24", availability_zone = "us-east-1a" }
    b = { cidr_block = "10.2.20.0/24", availability_zone = "us-east-1b" }
  }
}
run "production_plan" {
  command = plan
}
run "reject_unpinned_ami" {
  command = plan
  variables { ami_id = "" }
  expect_failures = [var.ami_id]
}
run "reject_single_production_instance" {
  command = plan
  variables { min_size = 1 }
  expect_failures = [var.min_size]
}
run "reject_wrong_certificate_region" {
  command = plan
  variables { certificate_arn = "arn:aws:acm:eu-west-1:123456789012:certificate/test" }
  expect_failures = [var.certificate_arn]
}
run "reject_no_rollout_headroom" {
  command = plan
  variables { max_size = 2 }
  expect_failures = [var.max_size]
}
run "reject_invalid_port" {
  command = plan
  variables { app_port = 65536 }
  expect_failures = [var.app_port]
}
