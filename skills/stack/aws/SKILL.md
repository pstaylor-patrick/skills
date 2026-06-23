---
name: stack:aws
description: AWS provider conventions for PST projects -- SSO auth, resource naming, Terraform patterns.
---

# AWS Stack Module

Depends on: `terraform` (auto-activated).

## Authentication

Always use AWS SSO profiles. Never hardcode access keys or use long-lived IAM user credentials.

```bash
aws sso login --profile <profile>   # run FOREGROUND -- never background this
export AWS_PROFILE=<profile>
```

The `--profile` flag must be explicit in all `aws` CLI calls and Terraform provider blocks.

## Terraform provider block

```hcl
provider "aws" {
  region  = var.aws_region
  profile = var.aws_profile
}
```

Never hardcode region or profile. Pass as variables with defaults only in non-prod workspaces.

## Resource naming

Pattern: `<project>-<env>-<resource-type>`. Example: `acme-prod-api-lambda`.

Tags on every resource: `Project`, `Environment`, `ManagedBy = terraform`.

## S3

- Block all public access on buckets unless explicitly public (CloudFront origin).
- Versioning enabled on state buckets and any bucket storing critical data.
- Lifecycle policies for non-current versions on state buckets.

## IAM

- Least privilege. No `*` actions or resources unless unavoidable (document why).
- Roles over users. No long-lived access keys.
- One role per service/Lambda/task. No shared roles across services.
