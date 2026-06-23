# AWS Reference

Deps tree: aws -> terraform (both auto-loaded)

## Common commands

- `aws sso login --profile <profile>` -- authenticate (FOREGROUND only)
- `aws sts get-caller-identity --profile <profile>` -- verify identity
- `aws s3 ls s3://<bucket> --profile <profile>` -- list bucket

## SSO setup

- `aws configure sso` -- initial profile setup
- Profiles stored in `~/.aws/config`
