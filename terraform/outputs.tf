output "api_endpoint" {
  value       = aws_apigatewayv2_api.api.api_endpoint
  description = "HTTP API used by the hosted frontend."
}
output "application_url" {
  value       = "https://${var.domain_name}"
  description = "Public HTTPS URL for the complete application."
}
output "cloudfront_url" {
  value       = "https://${aws_cloudfront_distribution.frontend.domain_name}"
  description = "CloudFront-generated URL, useful while diagnosing DNS."
}
output "cloudfront_distribution_id" {
  value       = aws_cloudfront_distribution.frontend.id
  description = "Distribution invalidated by the frontend delivery workflow."
}
output "certificate_arn" { value = aws_acm_certificate.frontend.arn }
output "frontend_bucket" { value = aws_s3_bucket.frontend.id }
output "source_bucket" { value = aws_s3_bucket.source.id }
output "processed_bucket" { value = aws_s3_bucket.processed.id }
output "processing_dlq_url" { value = aws_sqs_queue.dlq.url }
