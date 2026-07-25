output "state_bucket_name" {
  value       = aws_s3_bucket.terraform_state.id
  description = "Remote Terraform state bucket."
}

output "plan_role_arn" {
  value       = aws_iam_role.github_plan.arn
  description = "Set this as the GitHub repository variable AWS_PLAN_ROLE_ARN."
}

output "deploy_role_arn" {
  value       = aws_iam_role.github_deploy.arn
  description = "Set this as the GitHub repository variable AWS_DEPLOY_ROLE_ARN."
}

output "github_oidc_provider_arn" {
  value       = local.oidc_provider_arn
  description = "GitHub Actions OIDC provider used by both roles."
}

output "bootstrap_backend_migration_command" {
  value       = "cp bootstrap/backend.tf.example bootstrap/backend.tf && terraform -chdir=bootstrap init -migrate-state"
  description = "Run after the first bootstrap apply to move bootstrap state into S3."
}

