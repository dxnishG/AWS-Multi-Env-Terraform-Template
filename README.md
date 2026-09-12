# AWS application hosting stack with Terraform

This repository is a reusable Terraform root configuration for a small application-hosting stack on AWS. It creates a VPC, public and private subnets, routing, security groups, EC2 instances, an EC2 IAM instance profile, and encrypted S3 buckets. The same root configuration is used for `dev`, `acc`, and `prd`; each environment supplies its own `.tfvars` file.

Terraform state is stored in Terraform Cloud or Terraform Enterprise (TFC/TFE) through the `remote` backend. GitHub Actions runs security, correctness, formatting, validation, and plan checks for every push and pull request. Applies run only after a push to `main` or an explicit workflow dispatch with `run_apply` enabled.

## What it creates

- A VPC with DNS support enabled.
- Public subnets with an internet gateway and public route table.
- Private subnets with an optional single NAT Gateway and private route table.
- A web security group with configurable CIDR-based ingress rules.
- An app security group that accepts `app_port` from the web security group, plus optional CIDR rules.
- EC2 instances created from the `ec2_instances` map. `role = "web"` places an instance in a public subnet; `role = "app"` places it in a private subnet.
- An EC2 IAM role and instance profile with Systems Manager access. If S3 buckets are configured, the role also receives object and bucket-list permissions for those buckets.
- Optional RSA SSH key-pair generation. The generated private key is stored in Terraform state; see [Key-pair handling](#key-pair-handling).
- S3 buckets with AES-256 server-side encryption and public-access blocking. Versioning is enabled per bucket.

The template does not install an operating system application, create a load balancer, create a database, or configure DNS. AMIs, application deployment, patching, and monitoring remain outside this root configuration.

## Architecture

```mermaid
flowchart TB
  subgraph infrastructure[Terraform infrastructure]
    dev[dev.tfvars] --> root[Terraform root configuration]
    acc[acc.tfvars] --> root
    prd[prd.tfvars] --> root
    root --> vpc[VPC]
    vpc --> public[Public subnets]
    vpc --> private[Private subnets]
    public --> igw[Internet Gateway]
    private --> nat{NAT enabled?}
    nat -->|yes| natgw[NAT Gateway]
    web[Web EC2 instances] --> public
    app[App EC2 instances] --> private
    web --> websg[Web security group]
    app --> appsg[App security group]
    websg --> appsg
    root --> s3[Encrypted, private S3 buckets]
    root --> iam[EC2 instance role and profile]
    iam --> ssm[Systems Manager]
    iam --> s3
  end

  subgraph pipeline[GitHub Actions pipeline]
    change[Push or pull request] --> quality[Quality gate]
    quality --> tflint[TFLint<br/>Terraform and AWS rules]
    quality --> checkov[Checkov<br/>Security and compliance]
    quality --> trivy[Trivy<br/>Secrets and vulnerabilities]
    quality --> actionlint[actionlint<br/>Workflow correctness]
    tflint --> fmt[terraform fmt]
    checkov --> fmt
    trivy --> fmt
    actionlint --> fmt
    fmt --> validate[terraform validate]
    validate --> plans[Plan matrix<br/>dev / acc / prd]
    plans --> remote[TFC/TFE remote workspaces]
    remote --> deploygate{Deploy gate}
    deploygate -->|main or manual apply| approval[GitHub Environment approval]
    approval --> deploy[Serialized deploy matrix]
    deploy --> remote
  end

  remote --> root
```

The quality checks run in parallel and all must pass before the environment plan matrix starts. Plans also run in parallel, one per Terraform Cloud workspace. Deployment uses a serialized matrix (`max-parallel: 1`) and attaches each job to a GitHub Environment named for the target environment. Configure required reviewers on those GitHub Environments to add approval gates.

## Repository layout

```text
.
├── main.tf                       # Network, security, IAM, EC2, and S3 resources
├── variables.tf                  # Typed and validated input contract
├── output.tf                     # IDs, addresses, bucket names, and profile name
├── provider.tf                   # AWS region and default tags
├── backend.tf                    # Partial TFC/TFE remote backend
├── versions.tf                   # Terraform and provider constraints
├── envs/<env>/<env>.tfvars       # Environment infrastructure values
├── envs/<env>/<env>.tfconfig     # TFC/TFE hostname, organization, and workspace
├── .github/workflows/            # Quality, plan, and deployment workflows
├── .tflint.hcl                   # TFLint Terraform and AWS rules
├── .checkov.yml                  # Checkov security configuration
└── trivy.yaml                    # Trivy secret and vulnerability configuration
```

The CI workflow creates a temporary root-level `terraform.auto.tfvars` file from the selected environment file. It is ignored by Git and is used because the Terraform `remote` backend does not support passing run variables with `terraform plan -var-file` or `terraform apply -var-file`.

## Required authentication and secrets

There are two separate authentication paths. Do not put AWS access keys in GitHub Actions unless you intentionally choose a GitHub-to-AWS deployment design; this workflow delegates Terraform execution to TFC/TFE.

| Credential | Where it goes | Required for | Purpose |
|---|---|---|---|
| `TF_TOKEN` | GitHub repository secret: **Settings > Secrets and variables > Actions** | GitHub Actions | Lets the runner authenticate to TFC/TFE and trigger remote runs. |
| TFC/TFE user or team token | Local Terraform CLI credential store via `terraform login` | Local runs | Lets the local CLI initialize the remote backend and trigger plans/applies. |
| AWS credentials or dynamic provider credentials | TFC/TFE workspace or variable set | Remote plan/apply | Lets the TFC/TFE worker call AWS. Prefer short-lived dynamic credentials/OIDC. |

For static AWS credentials in TFC/TFE, configure these as **sensitive environment variables**, never in `.tfvars` or committed files:

```text
AWS_ACCESS_KEY_ID
AWS_SECRET_ACCESS_KEY
AWS_SESSION_TOKEN       # only for temporary credentials
```

`AWS_DEFAULT_REGION` is optional because the AWS provider uses `aws_region` from the selected `.tfvars` file. Set it as a workspace environment variable if other AWS tooling in the workspace needs it.

### Assume-role clarification

The repository does not define an AWS provider `assume_role` block. The `sts:AssumeRole` policy in `main.tf` is an EC2 service trust policy: it allows EC2 to assume the instance role after launch. It is not the role used by Terraform to deploy the stack.

For deployment through a role, configure TFC/TFE dynamic provider credentials/OIDC and grant the TFC/TFE identity permission to assume the target AWS role. Alternatively, provide an AWS credential chain supported by the TFC/TFE worker. The target role needs permissions for the resources in this repository, including VPC, EC2, IAM, S3, and Systems Manager operations.

## TFC/TFE setup

1. Create one workspace per environment, using a consistent naming pattern such as `<repository>-dev`, `<repository>-acc`, and `<repository>-prd`.
2. Set each workspace to **Remote** execution and leave **Version control workflow** disconnected. These workflows are CLI-driven by GitHub Actions; connecting the workspace directly to GitHub creates a second VCS-driven run that does not receive the selected environment file.
3. Assign the workspaces to a project in your TFC/TFE organization.
4. Assign an AWS credentials variable set to all workspaces. It must provide the sensitive environment variables `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY`.
5. Update the `organization` and workspace `name` in each `envs/<env>/<env>.tfconfig` file. Change `hostname` when using Terraform Enterprise.
6. Add `TF_TOKEN` to the GitHub repository secret store at **Settings > Secrets and variables > Actions**. This token authenticates GitHub Actions to Terraform Cloud; it is separate from the AWS credentials.
7. Ensure the AWS identity permits the Terraform resources in this repository, including VPC, EC2, IAM, S3, and Systems Manager operations.

The workspace names and backend config are intentionally separate from the infrastructure values. To reuse this template, copy an environment directory, change its organization and workspace name, then add that environment to `ENVIRONMENTS` in `.github/workflows/terraform.yml`.

## Local workflow

Prerequisites: Terraform `>= 1.5.0`, AWS permissions available to the selected TFC/TFE workspace, and access to the configured organization.

```bash
terraform login

ENV=dev
terraform init \
  -reconfigure \
  -backend-config="envs/${ENV}/${ENV}.tfconfig"

terraform fmt -check -recursive
terraform validate
cp "envs/${ENV}/${ENV}.tfvars" terraform.auto.tfvars
terraform plan

# Apply only after reviewing the plan.
terraform apply
```

The `cp` command creates the auto-loaded variables file required by the `remote` backend. Do not commit `terraform.auto.tfvars`; it is ignored by `.gitignore`. Use `terraform init -reconfigure` when switching between environment backends. Do not run different environments concurrently from the same working directory; each initialization changes the selected remote workspace.

## GitHub Actions workflow

- `terraform.yml` triggers on Terraform, environment, workflow, and quality-configuration changes.
- The reusable `terraform-quality.yml` workflow runs TFLint, Checkov, Trivy, and actionlint. Every quality job must pass before planning begins.
- Terraform planning runs `terraform fmt -check -recursive`, `terraform validate`, and a remote plan for each environment in the `ENVIRONMENTS` list (`dev`, `acc`, and `prd`).
- The TFC/TFE workspaces must be CLI-driven with no VCS repository connection. GitHub Actions is the single workflow trigger and passes the selected environment variables to each remote run.
- The workflow authenticates to Terraform Cloud using the GitHub repository secret `TF_TOKEN`. AWS credentials are provided to the remote Terraform Cloud workspaces by the assigned AWS credentials variable set.
- Each plan copies its matching `envs/<env>/<env>.tfvars` file to `terraform.auto.tfvars` before running `terraform plan`.
- A successful plan on a feature branch does not deploy. The reusable deploy workflow runs only after a push to `main`, or when a workflow is manually dispatched with `run_apply: true`.
- The deploy workflow applies the environments through a matrix with `max-parallel: 1`, using the same auto-loaded variable-file mechanism. This serializes deployments, but a matrix alone does not guarantee DEV → ACC → PRD start order.
- Each deploy matrix job sets `environment: <env>`, so GitHub records a separate deployment for each environment. Create matching environments under **Repository settings > Environments**; protection rules such as required reviewers can be configured there.
- Pull requests from forks cannot access repository secrets, so their remote plan jobs will not authenticate unless the workflow is adapted for that trust model.

## Key-pair handling

With `create_key_pair = true`, Terraform generates an RSA private key and stores it in Terraform state. Because remote state may contain the private key, protect the TFC/TFE workspace and state access accordingly. For production, consider managing the EC2 key pair outside Terraform and set:

```hcl
create_key_pair = false
key_name        = "an-existing-ec2-key-pair"
```

SSM access is enabled on every instance, so SSH is optional for normal administration.

## Important cost and deletion notes

- NAT Gateways and public IPv4 addresses incur AWS charges. `enable_nat_gateway` is disabled in the example `dev` environment and enabled in `acc` and `prd`.
- `force_destroy = true` allows Terraform to delete non-empty S3 buckets. Keep it `false` for important data.
- A single NAT Gateway is created in the first public subnet when enabled. This keeps the template simple but is not a multi-AZ NAT design.
- The default EC2 AMI lookup selects the most recent Amazon Linux 2023 x86_64 AMI in the configured region. Set `ami_id` to pin a known image.

## Reuse checklist

1. Copy `envs/dev` to a new environment directory.
2. Set a unique `environment`, CIDR ranges, AWS region, tags, and TFC/TFE workspace name.
3. Define public/private subnet keys that match each EC2 instance's `subnet_key`.
4. Keep web ingress narrow, especially SSH; prefer SSM instead of opening port 22.
5. Set S3 `purpose`, `enable_versioning`, and an intentional `force_destroy` value.
6. Add the environment to the workflow matrix and create a matching GitHub Environment with the same name.
7. Run a plan before applying.
