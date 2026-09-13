data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
data "aws_ec2_instance_type" "selected" {
  instance_type = var.instance_type
}
data "aws_ami" "selected" {
  owners = [data.aws_caller_identity.current.account_id]

  filter {
    name   = "image-id"
    values = [var.ami_id]
  }
}
resource "aws_security_group" "alb" {
  name_prefix = "${var.name}-alb-"
  description = "Public HTTPS entry point"
  vpc_id      = var.vpc_id
}
resource "aws_security_group" "app" {
  name_prefix = "${var.name}-app-"
  description = "Private application, ingress only from ALB"
  vpc_id      = var.vpc_id
}
resource "aws_vpc_security_group_ingress_rule" "https" {
  security_group_id = aws_security_group.alb.id
  description       = "Public HTTPS"
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
}
resource "aws_vpc_security_group_egress_rule" "alb" {
  security_group_id            = aws_security_group.alb.id
  description                  = "ALB to application and health endpoint"
  referenced_security_group_id = aws_security_group.app.id
  from_port                    = var.app_port
  to_port                      = var.app_port
  ip_protocol                  = "tcp"
}
resource "aws_vpc_security_group_ingress_rule" "app" {
  security_group_id            = aws_security_group.app.id
  description                  = "Application traffic only from ALB"
  referenced_security_group_id = aws_security_group.alb.id
  from_port                    = var.app_port
  to_port                      = var.app_port
  ip_protocol                  = "tcp"
}
resource "aws_vpc_security_group_egress_rule" "app_https" {
  security_group_id = aws_security_group.app.id
  description       = "HTTPS for SSM and application AWS APIs via NAT or endpoints"
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
}
# ALB access logs require SSE-S3, not SSE-KMS.
resource "aws_s3_bucket" "access_logs" {
  # checkov:skip=CKV_AWS_18:Terminal log sink; logging its own delivery would recurse.
  # checkov:skip=CKV_AWS_144:Regional access logs; cross-region retention belongs to the organization logging policy.
  # checkov:skip=CKV2_AWS_62:Passive log archive with no object-event consumer.
  # checkov:skip=CKV_AWS_145:ALB log delivery supports SSE-S3 only; this bucket contains access logs, not application data.
  bucket        = "${var.name}-alb-logs-${data.aws_caller_identity.current.account_id}-${data.aws_region.current.region}"
  force_destroy = true
}
# ALB log delivery can still be in flight when this bucket is destroyed; force_destroy alone
# occasionally loses that race, so drain all versions/delete markers immediately beforehand.
resource "null_resource" "drain_access_logs" {
  triggers = {
    bucket = aws_s3_bucket.access_logs.id
    region = data.aws_region.current.region
  }
  provisioner "local-exec" {
    when        = destroy
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      set -euo pipefail
      bucket="${self.triggers.bucket}"
      region="${self.triggers.region}"
      for attempt in 1 2 3 4 5; do
        versions=$(aws s3api list-object-versions --bucket "$bucket" --region "$region" --output json \
          --query '{Objects: Versions[].{Key:Key,VersionId:VersionId}}')
        markers=$(aws s3api list-object-versions --bucket "$bucket" --region "$region" --output json \
          --query '{Objects: DeleteMarkers[].{Key:Key,VersionId:VersionId}}')
        remaining=0
        if [ "$(echo "$versions" | jq '.Objects | length')" -gt 0 ]; then
          aws s3api delete-objects --bucket "$bucket" --region "$region" --delete "$versions"
          remaining=1
        fi
        if [ "$(echo "$markers" | jq '.Objects | length')" -gt 0 ]; then
          aws s3api delete-objects --bucket "$bucket" --region "$region" --delete "$markers"
          remaining=1
        fi
        [ "$remaining" -eq 0 ] && break
        sleep 5
      done
    EOT
  }
  depends_on = [aws_s3_bucket.access_logs]
}
resource "aws_s3_bucket_public_access_block" "access_logs" {
  bucket                  = aws_s3_bucket.access_logs.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
resource "aws_s3_bucket_server_side_encryption_configuration" "access_logs" {
  bucket = aws_s3_bucket.access_logs.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}
resource "aws_s3_bucket_versioning" "access_logs" {
  bucket = aws_s3_bucket.access_logs.id
  versioning_configuration {
    status = "Enabled"
  }
}
resource "aws_s3_bucket_lifecycle_configuration" "access_logs" {
  bucket = aws_s3_bucket.access_logs.id
  rule {
    id     = "retention"
    status = "Enabled"
    filter {}
    expiration {
      days = 90
    }
    noncurrent_version_expiration {
      noncurrent_days = 30
    }
    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
  depends_on = [aws_s3_bucket_versioning.access_logs]
}
data "aws_iam_policy_document" "access_logs" {
  statement {
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.access_logs.arn}/AWSLogs/${data.aws_caller_identity.current.account_id}/*"]
    principals {
      type        = "Service"
      identifiers = ["logdelivery.elasticloadbalancing.amazonaws.com"]
    }
  }
  statement {
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [aws_s3_bucket.access_logs.arn, "${aws_s3_bucket.access_logs.arn}/*"]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}
resource "aws_s3_bucket_policy" "access_logs" {
  bucket = aws_s3_bucket.access_logs.id
  policy = data.aws_iam_policy_document.access_logs.json
}
resource "aws_lb" "this" {
  # checkov:skip=CKV2_AWS_76:KnownBadInputs blocks Log4j; this check also demands AnonymousIpList, which would block legitimate VPN clients.
  name                       = var.name
  internal                   = false
  load_balancer_type         = "application"
  security_groups            = [aws_security_group.alb.id]
  subnets                    = var.public_subnet_ids
  enable_deletion_protection = var.enable_deletion_protection
  drop_invalid_header_fields = true
  desync_mitigation_mode     = "strictest"
  access_logs {
    bucket  = aws_s3_bucket.access_logs.id
    enabled = true
  }
  depends_on = [aws_s3_bucket_policy.access_logs, aws_s3_bucket_server_side_encryption_configuration.access_logs]
}
resource "aws_lb_target_group" "this" {
  name_prefix          = "app-"
  port                 = var.app_port
  protocol             = "HTTP"
  vpc_id               = var.vpc_id
  deregistration_delay = 60
  health_check {
    path                = var.health_check_path
    matcher             = "200"
    healthy_threshold   = 3
    unhealthy_threshold = 2
    interval            = 30
    timeout             = 5
  }
  lifecycle {
    create_before_destroy = true
  }
}
resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.this.arn
  port              = 443
  protocol          = "HTTPS"
  certificate_arn   = var.certificate_arn
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this.arn
  }
}
data "aws_iam_policy_document" "trust" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}
resource "aws_iam_role" "app" {
  name               = "${var.name}-application"
  assume_role_policy = data.aws_iam_policy_document.trust.json
}
resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.app.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}
data "aws_iam_policy_document" "storage" {
  count = length(var.bucket_arns) > 0 ? 1 : 0
  statement {
    actions   = ["s3:ListBucket"]
    resources = values(var.bucket_arns)
  }
  statement {
    actions   = ["s3:GetObject", "s3:PutObject"]
    resources = [for arn in var.bucket_arns : "${arn}/*"]
  }
  statement {
    actions   = ["kms:Decrypt", "kms:GenerateDataKey"]
    resources = [var.bucket_kms_key_arn]
    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["s3.${data.aws_region.current.region}.amazonaws.com"]
    }
  }
}
resource "aws_iam_role_policy" "storage" {
  count  = length(var.bucket_arns) > 0 ? 1 : 0
  role   = aws_iam_role.app.id
  policy = data.aws_iam_policy_document.storage[0].json
}
resource "aws_iam_instance_profile" "app" {
  name = "${var.name}-application"
  role = aws_iam_role.app.name
}
resource "aws_launch_template" "this" {
  name_prefix            = "${var.name}-"
  image_id               = var.ami_id
  instance_type          = var.instance_type
  ebs_optimized          = true
  update_default_version = true

  lifecycle {
    precondition {
      condition = contains(
        data.aws_ec2_instance_type.selected.supported_architectures,
        data.aws_ami.selected.architecture,
      )
      error_message = "instance_type architecture must match the application AMI architecture."
    }
  }
  iam_instance_profile {
    arn = aws_iam_instance_profile.app.arn
  }
  network_interfaces {
    associate_public_ip_address = false
    security_groups             = [aws_security_group.app.id]
    delete_on_termination       = true
  }
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
    instance_metadata_tags      = "disabled"
  }
  monitoring {
    enabled = true
  }
  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size           = 30
      volume_type           = "gp3"
      encrypted             = true
      delete_on_termination = true
    }
  }
  tag_specifications {
    resource_type = "instance"
    tags          = merge(var.tags, { Name = var.name, Backup = var.name })
  }
  tag_specifications {
    resource_type = "volume"
    tags          = merge(var.tags, { Name = var.name })
  }
}
resource "aws_autoscaling_group" "this" {
  name                      = "${var.name}-application"
  min_size                  = var.min_size
  max_size                  = var.max_size
  vpc_zone_identifier       = var.private_subnet_ids
  target_group_arns         = [aws_lb_target_group.this.arn]
  health_check_type         = "ELB"
  health_check_grace_period = 300
  default_instance_warmup   = 300
  min_elb_capacity          = var.min_size
  wait_for_capacity_timeout = "20m"
  enabled_metrics           = ["GroupDesiredCapacity", "GroupInServiceInstances"]
  launch_template {
    id      = aws_launch_template.this.id
    version = tostring(aws_launch_template.this.latest_version)
  }
  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 100
      max_healthy_percentage = 150
      instance_warmup        = 300
      auto_rollback          = true
      skip_matching          = true
    }
  }
  dynamic "tag" {
    for_each = merge(var.tags, { Name = var.name, Backup = var.name })
    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = true
    }
  }
  depends_on = [aws_lb_listener.https, aws_iam_role_policy_attachment.ssm]
}
resource "aws_autoscaling_policy" "cpu" {
  name                   = "${var.name}-cpu"
  autoscaling_group_name = aws_autoscaling_group.this.name
  policy_type            = "TargetTrackingScaling"
  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }
    target_value = 60
  }
}
resource "aws_cloudwatch_metric_alarm" "unhealthy" {
  alarm_name          = "${var.name}-unhealthy-targets"
  alarm_description   = "One or more targets failed readiness checks."
  namespace           = "AWS/ApplicationELB"
  metric_name         = "UnHealthyHostCount"
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 3
  comparison_operator = "GreaterThanThreshold"
  threshold           = 0
  treat_missing_data  = "breaching"
  dimensions          = { LoadBalancer = aws_lb.this.arn_suffix, TargetGroup = aws_lb_target_group.this.arn_suffix }
  alarm_actions       = [var.alarm_topic_arn]
  ok_actions          = [var.alarm_topic_arn]
}
resource "aws_cloudwatch_metric_alarm" "capacity" {
  alarm_name          = "${var.name}-low-healthy-capacity"
  namespace           = "AWS/ApplicationELB"
  metric_name         = "HealthyHostCount"
  statistic           = "Minimum"
  period              = 60
  evaluation_periods  = 3
  comparison_operator = "LessThanThreshold"
  threshold           = var.min_size
  treat_missing_data  = "breaching"
  dimensions          = { LoadBalancer = aws_lb.this.arn_suffix, TargetGroup = aws_lb_target_group.this.arn_suffix }
  alarm_actions       = [var.alarm_topic_arn]
  ok_actions          = [var.alarm_topic_arn]
}
resource "aws_cloudwatch_metric_alarm" "errors" {
  alarm_name          = "${var.name}-target-5xx"
  namespace           = "AWS/ApplicationELB"
  metric_name         = "HTTPCode_Target_5XX_Count"
  statistic           = "Sum"
  period              = 60
  evaluation_periods  = 3
  comparison_operator = "GreaterThanThreshold"
  threshold           = 10
  treat_missing_data  = "notBreaching"
  dimensions          = { LoadBalancer = aws_lb.this.arn_suffix }
  alarm_actions       = [var.alarm_topic_arn]
  ok_actions          = [var.alarm_topic_arn]
}
