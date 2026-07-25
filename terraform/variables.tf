variable "aws_region" {
  type    = string
  default = "us-east-1"
}
variable "project_name" {
  type    = string
  default = "cloud-image-pipeline"
}
variable "environment" {
  type    = string
  default = "dev"
}
variable "allowed_origins" {
  type        = list(string)
  default     = ["http://localhost:8080"]
  description = "Browser origins allowed to call the API and upload to S3."
}
variable "log_retention_days" {
  type    = number
  default = 14
}
variable "domain_name" {
  type        = string
  default     = "cloudwithliz.space"
  description = "Existing public Route 53 hosted zone and application domain."
}
