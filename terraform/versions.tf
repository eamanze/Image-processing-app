terraform {
  required_version = ">= 1.10.0"

  backend "s3" {
    bucket       = "cloud-image-pipeline-terraform-state-431655581157"
    key          = "cloud-image-pipeline/production/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }

  required_providers {
    aws    = { source = "hashicorp/aws", version = "~> 5.0" }
    random = { source = "hashicorp/random", version = "~> 3.6" }
  }
}

provider "aws" {
  region = var.aws_region
  default_tags { tags = { Project = var.project_name, ManagedBy = "Terraform", Environment = var.environment } }
}

# CloudFront accepts ACM certificates only from us-east-1, regardless of the
# region selected for the rest of the application.
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
  default_tags { tags = { Project = var.project_name, ManagedBy = "Terraform", Environment = var.environment } }
}
