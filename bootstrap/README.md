# Bootstrap — CI/CD Prerequisites

These resources **must exist before** GitHub Actions can run. They are the
backend + authentication that the repo's own Terraform depends on, so they
cannot be created by that Terraform (chicken-and-egg). Create them **once**,
manually, with admin AWS credentials.

## What gets created

| # | Resource | Name | Why |
|---|----------|------|-----|
| 1 | IAM OIDC provider | `token.actions.githubusercontent.com` | Lets GitHub Actions exchange its OIDC token for AWS creds |
| 2 | IAM role | `github-oidc-terraform-prometheus` | The `role-to-assume` in the workflow (`vars.AWS_ROLE_ARN`) |
| 3 | S3 bucket | `shivakrishna-tf-state-dev` | Remote Terraform state (see `../provider.tf`) |
| 4 | DynamoDB table | `vosukula-state-locking` | State locking (partition key `LockID`) |

## Run it

```bash
export AWS_REGION=us-east-1
cd bootstrap
chmod +x bootstrap.sh
./bootstrap.sh
```

The script is **idempotent** — safe to re-run; it skips resources that already exist.

## After running

1. Copy the printed role ARN.
2. In GitHub: **Settings → Secrets and variables → Actions → Variables tab → New repository variable**
   - Name: `AWS_ROLE_ARN`
   - Value: `arn:aws:iam::<ACCOUNT_ID>:role/github-oidc-terraform-prometheus`
   - It must be a **variable**, not a secret — the workflow reads `vars.AWS_ROLE_ARN`.
3. Re-run the failed **Terraform Plan** job.

## Why the original run failed

The workflow passes `role-to-assume: ${{ vars.AWS_ROLE_ARN }}`. When that variable
is unset, the value is empty, the credentials action finds no role (and no other
provider), and fails with:

```
Error: Credentials could not be loaded ... Could not load credentials from any providers
```

Setting `AWS_ROLE_ARN` to a real, existing role ARN (steps above) resolves it.

## Security note

`bootstrap.sh` attaches `PowerUserAccess` + `IAMFullAccess` to the role because
this project's Terraform creates IAM resources. That is broad. Once the pipeline
is green, **scope the role down** to least privilege (only the specific EC2, IAM,
and S3/DynamoDB actions your Terraform actually performs).
