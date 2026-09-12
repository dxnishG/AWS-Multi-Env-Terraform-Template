# AWS Multi-Environment Terraform Template

[![License](https://img.shields.io/badge/license-Apache--2.0-blue.svg)](LICENSE)

A production-oriented Terraform starter for running a stateless application on
AWS across development, acceptance, and production environments.

The template creates the same architecture in every environment, isolates state
in separate HCP Terraform or Terraform Enterprise workspaces, and promotes a
tested revision through **dev → acc → prd**.

> This repository provisions infrastructure around an application. It expects
> a tested application AMI, ACM certificate, DNS name, and operations SNS topic.
> It does not build the application or its AMI.

## Architecture

~~~mermaid
flowchart TB
    Internet((Internet))
    DNS[Route 53 or external DNS]
    subgraph AWS["AWS account / region"]
        WAF[AWS WAF<br/>managed rules + rate limit]
        SNS[Operations SNS topic]
        subgraph VPC["VPC"]
            ALB[Application Load Balancer<br/>HTTPS :443]
            subgraph PublicA["Public subnet · AZ A"]
                NATA[NAT Gateway]
            end
            subgraph PublicB["Public subnet · AZ B"]
                NATB[NAT Gateway]
            end
            subgraph PrivateA["Private subnet · AZ A"]
                EC2A[EC2 application instance]
            end
            subgraph PrivateB["Private subnet · AZ B"]
                EC2B[EC2 application instance]
            end

            ASG[Auto Scaling Group]
            S3EP[S3 gateway endpoint]
        end

        S3[(Versioned S3 buckets<br/>customer-managed KMS)]
        Backup[(AWS Backup vault<br/>daily EC2 recovery points)]
        Logs[(ALB + S3 access logs<br/>VPC flow logs + WAF logs)]
        CW[CloudWatch alarms]
        SSM[AWS Systems Manager]
    end

    Internet --> DNS --> WAF --> ALB
    ALB -->|HTTP on app_port| EC2A
    ALB -->|HTTP on app_port| EC2B
    ASG -. manages .-> EC2A
    ASG -. manages .-> EC2B
    EC2A --> NATA
    EC2B --> NATB
    EC2A --> S3EP --> S3
    EC2B --> S3EP
    SSM --> EC2A
    SSM --> EC2B
    EC2A -. snapshots .-> Backup
    EC2B -. snapshots .-> Backup
    ALB -. access logs .-> Logs
    WAF -. logs .-> Logs
    CW --> SNS
~~~

### What is included

- Two or more Availability Zones with one NAT gateway and private route table
  per AZ.
- Public HTTPS ALB with deletion protection, access logs, strict desync
  mitigation, TLS 1.2/1.3 policy, AWS managed WAF rules, and an IP rate limit.
- Private EC2 instances with no public IPs or SSH keys. Administration uses SSM.
- Auto Scaling with ELB health replacement, CPU target tracking, and rolling
  instance refresh with automatic rollback.
- IMDSv2, encrypted EBS volumes, detailed monitoring, and a pinned AMI.
- Versioned S3 buckets encrypted with a rotating customer-managed KMS key.
- VPC flow logs, WAF logs, S3 access logs, and CloudWatch health alarms.
- Daily AWS Backup recovery points retained for 35 days.
- Exact saved-plan deployment with ordered **dev → acc → prd** promotion.
- Terraform contract tests, TFLint, Checkov, Trivy, and actionlint in CI.

## Before you start

You need:

1. Terraform 1.9.x.
2. An AWS account for each environment, or one account with a deliberate
   isolation model.
3. An HCP Terraform or Terraform Enterprise organization with three
   CLI-driven workspaces.
4. A regional application AMI that:
   - contains the deployable application;
   - runs on boot;
   - listens on the configured app_port;
   - returns HTTP 200 from the configured health path;
   - includes a working SSM agent;
   - stores durable data outside the instance root volume.
5. An issued ACM certificate in each target account and region.
6. An SNS topic with at least one confirmed operations subscription.
7. A DNS hostname covered by the ACM certificate.

This architecture creates NAT gateways, an ALB, WAF resources, KMS keys, logs,
and backups in every environment. Review AWS pricing before deployment.

## Quick start

### 1. Create the remote workspaces

Create three CLI-driven workspaces:

- aws-app-dev
- aws-app-acc
- aws-app-prd

Keep VCS integration disconnected and automatic apply disabled. GitHub Actions
is the deployment controller.

Edit the backend files with your organization and workspace names:

~~~hcl
# envs/dev/dev.tfconfig
hostname     = "app.terraform.io"
organization = "YOUR_TERRAFORM_ORGANIZATION"

workspaces {
  name = "aws-app-dev"
}
~~~

Repeat for acc and prd. Change hostname when using Terraform Enterprise.

### 2. Configure AWS authentication

Configure short-lived AWS dynamic provider credentials in each remote
workspace. Prefer one deployment role per environment and separate AWS accounts.
Do not store AWS access keys in this repository or GitHub Actions.

The deployment identity needs permissions for VPC, EC2, Auto Scaling, ELB,
WAFv2, IAM, S3, KMS, CloudWatch Logs and alarms, AWS Backup, and Systems Manager
resources declared by this repository.

### 3. Set required workspace variables

Create these Terraform variables in every remote workspace:

| Variable | Example | Purpose |
| --- | --- | --- |
| aws_account_id | 123456789012 | Prevents deployment to the wrong AWS account |
| ami_id | ami-0123456789abcdef0 | Pins the tested application image |
| certificate_arn | arn:aws:acm:us-east-1:123456789012:certificate/... | Enables the HTTPS listener |
| alarm_topic_arn | arn:aws:sns:us-east-1:123456789012:operations | Receives health and backup alarms |

These values are environment-specific and intentionally absent from committed
tfvars files. They are identifiers rather than application secrets, but
workspace variables prevent accidental reuse across accounts and regions.

### 4. Customize each environment

Edit:

- envs/dev/dev.tfvars
- envs/acc/acc.tfvars
- envs/prd/prd.tfvars

At minimum, change name_prefix, CIDRs, Availability Zones, instance type,
capacity, bucket definitions, and tags. name_prefix becomes part of globally
unique S3 bucket names, so use a value specific to your organization/application.

Public and private subnet maps must contain at least two distinct Availability
Zones. Every private subnet must have a public subnet in the same AZ.

### 5. Run local validation

~~~bash
terraform init -backend=false -input=false -lockfile=readonly
terraform fmt -check -recursive
terraform validate
terraform test
~~~

The tests use Terraform mock providers. They validate module contracts without
AWS credentials or live infrastructure.

### 6. Review the first environment plan

~~~bash
terraform login
cp envs/dev/dev.tfvars terraform.auto.tfvars

terraform init \
  -reconfigure \
  -input=false \
  -lockfile=readonly \
  -backend-config=envs/dev/dev.tfconfig

terraform plan -out=deployment.tfplan
terraform apply deployment.tfplan
~~~

The last command applies the exact saved remote plan. Remove
terraform.auto.tfvars before switching environments, or use separate working
directories. The file and plan artifacts are ignored by Git.

After the apply, create a DNS alias/CNAME from the application hostname to the
application_dns_name output and verify the HTTPS health endpoint.

## GitHub Actions setup

Pushes and pull requests run the quality gate and a Terraform plan for each
environment: dev, acc, and prd. A push to main starts the promotion sequence;
only then can Terraform apply run.

### Repository settings

| Type | Name | Value |
| --- | --- | --- |
| Secret | TF_TOKEN | HCP Terraform/TFE token limited to the three workspaces |
| Variable | TF_HOSTNAME | TFE hostname; omit for app.terraform.io |

Create GitHub environments named dev, acc, and prd under
**Settings → Environments**. Add these variables to each environment:

| Name | Value |
| --- | --- |
| APPLICATION_URL | Full readiness URL, for example https://app.example.com/health |
| AWS_VERIFY_ROLE_ARN | Read-only AWS role assumed through GitHub OIDC |

The verification role needs:

~~~json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Action": [
      "autoscaling:DescribeAutoScalingGroups",
      "autoscaling:DescribeInstanceRefreshes",
      "elasticloadbalancing:DescribeTargetHealth"
    ],
    "Resource": "*"
  }]
}
~~~

Restrict its GitHub OIDC trust to:

~~~text
repo:OWNER/REPOSITORY:environment:ENVIRONMENT
~~~

For prd, configure required reviewers, prevention of self-review, and a
deployment branch policy allowing main. Disable administrator bypass where your
GitHub plan supports it. The workflow checks the first three controls before
creating a production plan.

Protect main separately with pull-request reviews and required quality checks.

### Promotion sequence

~~~mermaid
sequenceDiagram
    actor Operator
    participant GH as GitHub Actions
    participant TF as HCP Terraform/TFE
    participant AWS

    Operator->>GH: Dispatch from main with deploy=true
    GH->>GH: Quality and security checks
    GH->>GH: Plan dev, acc, and prd
    loop dev, then acc, then prd
        GH->>TF: Create saved remote plan
        TF->>AWS: Refresh current state
        TF-->>GH: Saved plan reference
        GH->>GH: Wait for environment approval
        GH->>TF: Apply that exact saved plan
        TF->>AWS: Reconcile infrastructure
        GH->>AWS: Verify ASG version and ALB targets
        GH->>AWS: Require 3 successful HTTPS health checks
    end
~~~

A failed plan prevents deployment. A failed environment stops the promotion.
The rollout gate waits up to 30 minutes and rejects failed/rolled-back instance refreshes, stale launch-template versions, insufficient capacity, unhealthy targets, and failed HTTPS readiness.

## Configuration reference

| Input | Type | Default | Notes |
| --- | --- | --- | --- |
| environment | string | required | One of dev, acc, prd |
| aws_region | string | required | Must match AMI, ACM certificate, and SNS topic |
| aws_account_id | string | required | Enforced by allowed_account_ids |
| name_prefix | string | app | 2–16 lowercase letters, digits, or hyphens |
| vpc_cidr | string | required | IPv4 VPC CIDR |
| public_subnet_configs | map(object) | required | At least two subnets in distinct AZs |
| private_subnet_configs | map(object) | required | At least two; AZs must match public subnets |
| ami_id | string | required | No latest-AMI fallback |
| certificate_arn | string | required | ACM ARN in target account/region |
| alarm_topic_arn | string | required | SNS ARN in target account/region |
| instance_type | string | t3.small | Must be compatible with the AMI |
| app_port | number | 8080 | Reachable only from the ALB |
| health_check_path | string | /health | Must begin with / |
| min_size | number | 2 | Production rejects values below two |
| max_size | number | 4 | Must exceed min_size for rolling headroom |
| s3_buckets | map(object) | assets bucket | Buckets are versioned and protected |
| tags | map(string) | empty map | Merged with environment/management tags |

### Outputs

| Output | Description |
| --- | --- |
| application_dns_name | ALB hostname used by your DNS record |
| autoscaling_group_name | Application Auto Scaling group |
| vpc_id | Environment VPC |
| public_subnet_ids | Public subnet IDs by configured key |
| private_subnet_ids | Private subnet IDs by configured key |
| s3_bucket_names | Application bucket names |
| backup_vault_name | AWS Backup vault |
| target_group_arn | Used by rollout verification |
| launch_template_version | Expected version after deployment |

## Repository structure

~~~text
.
├── main.tf                         # Composes the four modules
├── variables.tf / output.tf       # Public root-module contract
├── provider.tf / versions.tf      # AWS provider and version constraints
├── backend.tf                     # Partial HCP Terraform/TFE backend
├── envs/
│   ├── dev/
│   ├── acc/
│   └── prd/                       # Values and backend config per environment
├── modules/
│   ├── network/
│   ├── service/
│   ├── storage/
│   └── recovery/
├── tests/                         # Terraform contract tests
├── .github/
│   ├── scripts/                   # CI rollout verifier and its unit test
│   └── workflows/                 # Quality, saved-plan, and promotion workflows
└── docs/                          # Migration, operations, and security notes
~~~

The root tests directory is intentional: terraform test discovers tftest.hcl
files there. CI-only Python code lives under .github/scripts so the public
module surface stays uncluttered.

## Security and operational notes

- S3 data buckets and KMS keys use Terraform prevent_destroy; ALB deletion
  protection is enabled. Decommissioning requires an explicit reviewed change.
- The application instance role can read/write configured bucket objects but
  cannot delete them.
- HTTP is used only between the ALB and instances inside the VPC. Add end-to-end
  TLS if your threat model requires it.
- WAF managed-rule false positives should be tested in dev and acc.
- Backup recovery points remain in the same account and region. Add a separately
  owned cross-account/cross-region vault when required by your RPO/RTO.
- VPC, ALB, WAF, and S3 logs do not replace application logs and metrics.
- This template supports the standard commercial AWS partition.

Read:

- [Operations and recovery](docs/OPERATIONS.md)
- [Security scanner exceptions](docs/SECURITY.md)
- [Migration from the earlier non-modular version](docs/MIGRATION.md)

## Updating and extending

Keep the root module as composition glue. Add reusable AWS behavior inside the
module that owns it, expose only needed inputs/outputs, update contract tests,
and run the full quality suite before publishing changes.

Dependabot checks GitHub Actions and Terraform dependencies weekly. GitHub
Actions are pinned to immutable commit SHAs; review and merge Dependabot updates
to move those pins.

If you are starting fresh, ignore the migration example under docs. If you
already deployed the earlier repository version, follow the migration guide
before planning: standalone EC2 instances cannot be converted in place to an
Auto Scaling group.

## License

Licensed under the [Apache License 2.0](LICENSE). It permits commercial use,
modification, and redistribution while preserving license and attribution
notices and providing an explicit contributor patent grant.
