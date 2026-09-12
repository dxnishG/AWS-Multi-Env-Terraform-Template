# Operations and recovery

## Production acceptance

- Test the regional copies of the same application AMI through DEV and ACC.
- Verify ACM/DNS/WAF, healthy targets in both AZs, SSM, IAM access and the SNS subscription.
- Exercise target failure and a rolling update. Verify replacement and alarms. Load-test and tune capacity, health checks and warmup.
- Confirm a completed AWS Backup job and restore drill. Record measured RPO/RTO, recovery-point ARN, owner and date in your operations system.
- Configure account CloudTrail/security monitoring, budgets and application telemetry. Network/ALB/WAF logs do not replace application logs.

## Failed deployment

Stop promotion. Inspect the remote run, instance refresh, target health, application logs and alarms. After auto-rollback, restore the previous AMI input and create/review a new plan: Terraform still expresses the attempted version. Do not force-unlock active runs. Discard abandoned pending saved plans using normal HCP Terraform run controls.

The gate intentionally fails after rollback even when the old version serves traffic. An old failed refresh also needs operator investigation before promotion.

## EC2 restore drill

1. Select a completed recovery point from the environment vault.
2. Use a separately controlled restore role with EC2 restore permissions and required KMS permissions. The template role has backup permissions only.
3. Restore into an isolated private subnet/security group. Do not register it with production target groups or assign a public IP.
4. Verify filesystem/application integrity and recover data. Snapshots are crash-consistent, not database-consistent.
5. Recover through the application's normal process or repair the AMI. Do not substitute a restored pet instance for a working ASG image.
6. Record duration/data loss and explicitly clean up drill resources.

Snapshots run daily with 35-day retention and select EC2 tagged Backup=<name>. They are in the same account/region. Add cross-account/region backup for those failure modes and test restoration. The failed-job alarm does not prove scheduling occurred: monitor recovery-point age and backup compliance operationally.

## S3 object recovery

Inspect versions, then copy the selected version to the live key. For deletion, inspect the delete marker before removing it. The application role cannot delete versions. Keep all required KMS keys available; old objects may use an earlier key. Use independent backups when same-bucket versioning cannot meet recovery requirements.

## Decommission

Archive required data and follow operational authorization. Remove deletion guards and ALB protection in a reviewed change. Empty/version cleanup and vault cleanup are explicit operator actions; force deletion is disabled. Schedule KMS deletion only when retained ciphertext is no longer required.
