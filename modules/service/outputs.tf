output "dns_name" {
  description = "dns name produced by this module."
  value       = aws_lb.this.dns_name
}

output "asg_name" {
  description = "asg name produced by this module."
  value       = aws_autoscaling_group.this.name
}
output "target_group_arn" {
  description = "Application target group ARN."
  value       = aws_lb_target_group.this.arn
}
output "launch_template_version" {
  description = "Pinned launch template version."
  value       = tostring(aws_launch_template.this.latest_version)
}
