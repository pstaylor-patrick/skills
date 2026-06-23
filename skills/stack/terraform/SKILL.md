---
name: stack:terraform
description: Terraform conventions for PST projects -- HCL style, state, provider config.
---

# Terraform Stack Module

## HCL conventions

- One resource per file where practical. Group tightly-coupled resources.
- File naming: `main.tf` (root config), `variables.tf`, `outputs.tf`, `providers.tf`, `versions.tf`.
- Use `locals {}` to DRY repeated expressions. No inline arithmetic in resource args.
- All variables must have `description` and `type`. `default` only when safe to omit at apply time.

## State

- Remote state only (S3 + DynamoDB lock, or Terraform Cloud). Never commit `.tfstate`.
- `.gitignore`: `*.tfstate`, `*.tfstate.backup`, `.terraform/`, `*.tfvars` (use `*.tfvars.example`).

## Providers

- Pin provider versions with `~>` (minor-compatible). Document why in `versions.tf`.
- No hardcoded credentials in HCL. Use environment variables or provider-native auth.

## Plan before apply

- Always `terraform plan -out=tfplan` and review before `terraform apply tfplan`.
- In CI: `terraform plan` on PR, `terraform apply` only on merge to main.

## No cloud deps in modules

Modules must be self-contained. Pass every cloud-specific value in as a variable. No `data` sources that reach out to AWS/GCP inside a shared module.
