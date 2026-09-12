# Migrating a v1 deployment

This is a compute architecture change. Do not use an unattended first apply against an existing workspace.

1. Pause deployments. Securely export current state and record old EC2 IDs, security groups, role, profile and key-pair name. State may contain a generated SSH private key: keep it out of Git, artifacts and chat. Confirm a recovery point.
2. Copy `docs/migration-v1.tf.example` to the repository root as `migrations.tf`. Preserve prefixes, CIDRs, subnet keys and bucket keys. The mappings assume the original web-1a/app-1a keys for the existing NAT/private route table. Adapt every address if customized.
3. Prepare the application AMI, ACM, DNS and SNS inputs. The application must handle proxy headers and persist data outside its root disk.
4. Review the plan. Existing VPC/subnets/data buckets should not be replaced. A second NAT/route table, ALB, ASG and operational resources are expected. The second private subnet switches to its local NAT; assess active connections. New default S3 encryption affects future writes; old objects retain their old encryption.
5. Removed blocks use destroy=false. Legacy EC2, security groups, IAM role/policies/profile and key resources are forgotten without deleting AWS resources, preserving the old service for cutover. Inventory first. If continuous management is needed, import these into a dedicated legacy workspace before proceeding.
6. Apply the reviewed plan. Verify target health, SSM, IAM data access, alarms and backups. Use a test hostname first, then switch traffic/DNS and observe.
7. Keep the old service for the rollback window. Roll back DNS if needed; do not reverse the state migration by checking out v1.
8. Explicitly retire legacy compute/IAM/key resources after acceptance, using the inventory. Review attached volumes and data. No repository script deletes the old stack automatically.
9. Remove the temporary root `migrations.tf` after every environment has consumed the state moves. Keep the documented example for reference.

Terraform prevent_destroy protects a resource only while its declaration remains. It is not an AWS authorization boundary. Removing a module or guard can bypass it; restrict deployment roles and state access too.

For heavily customized stacks, use a fresh workspace with unique prefix/CIDR and an explicit data/traffic cutover. Do not reuse existing bucket names in the fresh stack.
