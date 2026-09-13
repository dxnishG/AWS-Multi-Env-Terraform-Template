# output "vpc_id" {
#   description = "VPC ID."
#   value       = module.network.vpc_id
# }
# output "public_subnet_ids" {
#   description = "Public subnet IDs by logical key."
#   value       = module.network.public_subnet_ids
# }
# output "private_subnet_ids" {
#   description = "Private subnet IDs by logical key."
#   value       = module.network.private_subnet_ids
# }
# output "application_dns_name" {
#   description = "ALB DNS name; create an alias for the hostname covered by the ACM certificate."
#   value       = module.service.dns_name
# }
# output "autoscaling_group_name" {
#   description = "ASG to inspect for rollout completion."
#   value       = module.service.asg_name
# }
# output "s3_bucket_names" {
#   description = "Data bucket names."
#   value       = module.storage.bucket_names
# }
# output "backup_vault_name" {
#   description = "Vault holding scheduled EC2 recovery points."
#   value       = module.recovery.vault_name
# }
output "aws_region" {
  description = "Deployment region for rollout verification."
  value       = var.aws_region
}
# output "target_group_arn" {
#   description = "Target group checked by the deployment gate."
#   value       = module.service.target_group_arn
# }
# output "launch_template_version" {
#   description = "Expected launch template version after rollout."
#   value       = module.service.launch_template_version
# }
