variable "aws_region" {
  type        = string
  default     = "us-east-1"
  description = "Region for the Terraform state bucket."
}

variable "github_owner" {
  type        = string
  description = "GitHub username or organization that owns the repository."

  validation {
    condition     = length(trimspace(var.github_owner)) > 0
    error_message = "github_owner must not be empty."
  }
}

variable "github_owner_id" {
  type        = string
  description = "Immutable GitHub ID of the repository owner, as included in the customized OIDC subject."

  validation {
    condition     = can(regex("^[0-9]+$", var.github_owner_id))
    error_message = "github_owner_id must contain only digits."
  }
}

variable "github_repository" {
  type        = string
  description = "GitHub repository name without the owner."

  validation {
    condition     = length(trimspace(var.github_repository)) > 0
    error_message = "github_repository must not be empty."
  }
}

variable "github_repository_id" {
  type        = string
  description = "Immutable GitHub repository ID, as included in the customized OIDC subject."

  validation {
    condition     = can(regex("^[0-9]+$", var.github_repository_id))
    error_message = "github_repository_id must contain only digits."
  }
}

variable "create_github_oidc_provider" {
  type        = bool
  default     = true
  description = "Set false when token.actions.githubusercontent.com is already registered in this AWS account."
}

variable "state_bucket_name" {
  type        = string
  default     = "cloud-image-pipeline-terraform-state-431655581157"
  description = "Globally unique bucket used by the application and bootstrap Terraform states."
}
