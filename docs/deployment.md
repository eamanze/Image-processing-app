# Deployment guide

This project uses four GitHub Actions workflows and short-lived AWS credentials through GitHub OIDC:

| Workflow | Trigger | Responsibility |
|---|---|---|
| `ci.yml` | Pull requests and pushes | Tests, syntax checks, Terraform validation, and an optional PR plan |
| `infrastructure.yml` | Changes to `terraform/`, `src/`, or Lambda packaging on `main`; manual plan/apply | Terraform infrastructure and Lambda deployment, followed by initial frontend population |
| `frontend.yml` | Changes to `frontend/` on `main`; manual | Static asset upload and CloudFront invalidation |
| `destroy.yml` | Manual only | Approval-gated destruction with typed confirmation |

Terraform owns AWS resources. The frontend workflow owns the objects stored in the frontend bucket. All workflows share one encrypted remote state and deployment workflows use one concurrency group so production mutations do not overlap.

## Prerequisites

- AWS account `431655581157`
- Public Route 53 hosted zone for `cloudwithliz.space`
- A GitHub repository containing this project
- AWS CLI, Terraform 1.10+, Docker, Git, and `zip` for one-time local setup
- An AWS identity allowed to create S3 buckets, IAM OIDC providers, roles, and policies

Verify the local tools and AWS identity:

```bash
aws --version
terraform version
docker --version
aws sts get-caller-identity
```

## 1. Configure the bootstrap stack

The separate `bootstrap/` Terraform stack creates everything the application pipeline needs before it can run:

- private, encrypted, versioned S3 state bucket;
- S3-native state and lock-file permissions;
- GitHub Actions OIDC identity provider;
- read-only planning role for pull requests and manual plans;
- protected deployment role for apply, frontend, and destroy workflows;
- project-scoped deployment permissions.

Copy the example variables:

```bash
cp bootstrap/terraform.tfvars.example bootstrap/terraform.tfvars
```

Edit `bootstrap/terraform.tfvars`:

```hcl
github_owner         = "YOUR_GITHUB_USERNAME_OR_ORG"
github_owner_id      = "YOUR_GITHUB_OWNER_ID"
github_repository    = "YOUR_REPOSITORY_NAME"
github_repository_id = "YOUR_GITHUB_REPOSITORY_ID"

create_github_oidc_provider = true
```

This repository uses customized GitHub OIDC subjects that bind both names to
their immutable IDs. Read the `sub` claim from a diagnostic workflow run and
copy the IDs following the owner and repository names. For example,
`repo:OWNER@123/REPOSITORY@456:environment:production` uses owner ID `123` and
repository ID `456`.

Check whether the AWS account already has the GitHub provider:

```bash
aws iam list-open-id-connect-providers
```

If an ARN ends with `oidc-provider/token.actions.githubusercontent.com`, change the variable to:

```hcl
create_github_oidc_provider = false
```

This makes Terraform reference the existing account-level provider instead of attempting to create a duplicate.

## 2. Apply the bootstrap stack

The first bootstrap apply intentionally uses local state because its remote bucket does not exist yet:

```bash
terraform -chdir=bootstrap init
terraform -chdir=bootstrap fmt -check
terraform -chdir=bootstrap validate
terraform -chdir=bootstrap plan -out=bootstrap.tfplan
terraform -chdir=bootstrap apply bootstrap.tfplan
```

The state bucket has `prevent_destroy = true`. An application or bootstrap destroy cannot accidentally remove deployment history.

Inspect the outputs:

```bash
terraform -chdir=bootstrap output
```

Expected role names:

```text
CloudImagePipelinePlanRole
CloudImagePipelineDeployRole
```

## 3. Migrate bootstrap state to S3

After the first apply, copy the prepared backend file and migrate the local bootstrap state:

```bash
cp bootstrap/backend.tf.example bootstrap/backend.tf
terraform -chdir=bootstrap init -migrate-state
```

Accept the prompt to copy state. Verify it:

```bash
terraform -chdir=bootstrap state list
aws s3 ls s3://cloud-image-pipeline-terraform-state-431655581157/bootstrap/
```

`bootstrap/backend.tf` is ignored by Git because the tracked example is the canonical configuration.

## 4. Initialize or migrate application state

If the application has never been applied:

```bash
terraform -chdir=terraform init -reconfigure
```

If an existing local `terraform/terraform.tfstate` manages deployed resources, migrate it:

```bash
terraform -chdir=terraform init -migrate-state
```

Accept the state-copy prompt and check:

```bash
terraform -chdir=terraform state list
```

Do not apply against an empty remote state if the same resources are already deployed. Migrate the existing state first.

The two remote state keys are:

```text
bootstrap/terraform.tfstate
cloud-image-pipeline/production/terraform.tfstate
```

## 5. Understand the generated permissions

The planning role receives AWS `ReadOnlyAccess` plus narrowly scoped access to the two state files and their `.tflock` objects. It trusts only same-repository pull requests and manual plans on `main`.

The deployment role trusts only the protected GitHub environments `production` and `production-destroy`. Its custom policy manages the services used by this project, restricts application S3 buckets to `cloud-image-pipeline-dev-*`, IAM roles to `cloud-image-pipeline-*`, and Route 53 record changes to hosted zone `Z05717301OIDAACFNTRQO`. The state bucket does not match the application-bucket pattern and is accessible only through the narrower state policy.

Review `bootstrap/main.tf` before applying. The actions for global services such as CloudFront, ACM, API Gateway, Lambda, CloudWatch, and SQS use `Resource = "*"` where resource identifiers are not known until the application is created or service authorization requires it. The role is still isolated by its GitHub trust policy and protected environments.

## 6. Configure GitHub repository variables

In GitHub, open **Settings → Secrets and variables → Actions → Variables** and add:

| Variable | Value |
|---|---|
| `AWS_PLAN_ROLE_ARN` | `arn:aws:iam::431655581157:role/CloudImagePipelinePlanRole` |
| `AWS_DEPLOY_ROLE_ARN` | `arn:aws:iam::431655581157:role/CloudImagePipelineDeployRole` |

These are identifiers, not credentials. Do not create `AWS_ACCESS_KEY_ID` or `AWS_SECRET_ACCESS_KEY` secrets; OIDC supplies temporary credentials.

## 7. Create protected GitHub environments

Open **Settings → Environments**.

Create `production`:

1. Add required reviewers.
2. Restrict deployment branches to `main`.
3. Optionally add a wait timer.

Create `production-destroy`:

1. Add required reviewers.
2. Restrict deployment branches to `main`.
3. Use stricter reviewers than normal deployment if possible.

The apply and frontend jobs use `production`. Destruction uses `production-destroy` and additionally requires the typed value `destroy-cloudwithliz.space`.

## 8. Commit and push the pipeline

Commit these files to a feature branch:

```bash
git add .github terraform scripts docs README.md
git commit -m "Add OIDC GitHub deployment pipelines"
git push -u origin HEAD
```

Open a pull request. CI runs tests and validation. A same-repository PR also runs a speculative plan when `AWS_PLAN_ROLE_ARN` is available; plans from forks are skipped so untrusted code cannot obtain AWS credentials.

Review and merge the pull request to `main`.

## 9. First infrastructure deployment

Changes under `terraform/`, `src/`, or the Lambda packaging script automatically start **Infrastructure** after merge to `main`.

1. Open **Actions → Infrastructure**.
2. Open the pending `production` deployment.
3. Review and approve it.
4. The workflow tests the code, packages Linux-compatible Lambda ZIPs, creates a saved Terraform plan, applies it, and calls `scripts/deploy-frontend.sh`.
5. The frontend script reads Terraform outputs, generates production `config.js`, uploads static files, and invalidates CloudFront.

Run a plan without applying at any time through **Run workflow → action: plan**. Choose `apply` for an explicitly requested manual deployment.

After apply completes, verify:

```bash
curl -I https://cloudwithliz.space
```

CloudFront and a new ACM certificate can require several minutes on the first deployment.

## 10. Normal frontend deployment

A merge to `main` that changes `frontend/**` starts **Frontend**:

1. JavaScript syntax is checked.
2. GitHub assumes the deployment role using OIDC.
3. Terraform reads the existing remote-state outputs.
4. `config.js` is generated with the deployed API endpoint.
5. HTML, CSS, and JavaScript are uploaded to the private frontend bucket.
6. A CloudFront `/*` invalidation is created.

The workflow can also be started manually from **Actions → Frontend → Run workflow**.

## 11. Normal Lambda or infrastructure deployment

Changes to `src/**`, `terraform/**`, or `scripts/package-lambdas.sh` start **Infrastructure**. Lambda packages remain Terraform-owned through `source_code_hash`; this ensures a code change produces a reviewed infrastructure plan and a traceable Lambda update.

The infrastructure workflow repopulates the frontend after every apply. This matters when a frontend bucket is created or replaced even if no frontend source file changed.

## 12. Destroy the application

Destruction is never triggered by a push.

1. Open **Actions → Destroy infrastructure**.
2. Select **Run workflow** on `main`.
3. Enter exactly `destroy-cloudwithliz.space`.
4. Approve the `production-destroy` environment request.
5. The workflow saves a destroy plan and applies that exact plan.

The application resources and DNS records are removed. The existing Route 53 hosted zone and the separate Terraform state bucket remain. Retaining the state bucket preserves audit and recovery history.

## 13. Troubleshooting

### OIDC access denied

Compare the IAM trust-policy `sub` with the job. This repository's customized
OIDC subject prefix is `repo:OWNER@OWNER_ID/REPOSITORY@REPOSITORY_ID`:

- PR plan: `repo:OWNER@OWNER_ID/REPOSITORY@REPOSITORY_ID:pull_request`
- Manual plan on main: `repo:OWNER@OWNER_ID/REPOSITORY@REPOSITORY_ID:ref:refs/heads/main`
- Apply/frontend: `repo:OWNER@OWNER_ID/REPOSITORY@REPOSITORY_ID:environment:production`
- Destroy: `repo:OWNER@OWNER_ID/REPOSITORY@REPOSITORY_ID:environment:production-destroy`

Also confirm the audience is `sts.amazonaws.com`.

### Backend initialization fails

Confirm the state bucket exists, the role can list it, and the role can access both the state key and `.tflock` key.

### Frontend deployment cannot find outputs

The infrastructure must be applied first. Check:

```bash
terraform -chdir=terraform output
```

### Site still shows old assets

Inspect the Frontend workflow's CloudFront invalidation step and wait for invalidation completion. The script assigns short cache headers and invalidates all paths after upload.

### Infrastructure and frontend changes are in the same commit

Both workflows may be queued, but the shared `cloud-image-pipeline-production` concurrency group serializes them. The infrastructure workflow also deploys the frontend, so the final content remains consistent.
