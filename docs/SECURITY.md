# Security scanner exceptions

Checkov scans the repository explicitly. There are no globally disabled
checks. Exceptions live on the specific resource that needs them.

| Checks | Scope and reason |
| --- | --- |
| CKV_AWS_109 / 111 / 356 | Four KMS resource policy documents. Resource wildcard means only the attached key. The account root principal enables IAM delegation; it does not give every identity access. Log service grants also constrain the encryption context. |
| CKV_AWS_145 | ALB and S3 server-access-log sinks use SSE-S3 for delivery compatibility. Application buckets use a customer-managed KMS key. |
| CKV_AWS_18 | Terminal log buckets do not recursively log their own deliveries. Application data buckets have server access logging. |
| CKV_AWS_144 | Cross-region replication needs a separately owned destination and a recovery policy. This baseline is regional. |
| CKV2_AWS_62 | Passive logs and application buckets have no defined object-event consumer. Add event notifications alongside the consuming workload. |
| CKV2_AWS_76 | The ALB has WAF KnownBadInputs for Log4j. Checkov also requires AnonymousIpList, which would exclude legitimate VPN users. The WAF resource itself passes CKV_AWS_192. |

Review exceptions when requirements change. Logs may contain personal data:
ALB and S3 audit access must be restricted, and application URLs should never
contain secrets. WAF authorization/cookie headers are redacted and request
sampling is disabled.

Only AWS commercial partitions are currently supported. IAM deployment
permissions, GitHub branch/environment administration, HCP Terraform policy
sets and AWS organization guardrails must be configured by the platform owner.
The template's account allowlist prevents accidental wrong-account deployment
but does not replace least-privilege deployment credentials.
