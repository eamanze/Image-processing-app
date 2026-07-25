# Operations runbook

## Healthy signal

A healthy deployment serves `https://cloudwithliz.space` with a valid certificate. An upload returns `201`, the S3 object triggers one processor invocation, and `GET /images/{key}` changes from `202 processing` to `200 ready`. Processor logs contain `image_processed` with source and destination keys.

## Investigate a failed image

1. Search the processor CloudWatch log group by the object key.
2. Inspect the `processing_failed` exception (common causes: invalid image or size limit).
3. Check the `processor-errors` alarm and SQS dead-letter queue.
4. After correcting a transient/configuration issue, redrive the DLQ message or copy the source object to a new key to emit another event.

## Common issues

- Browser CORS error: ensure its exact origin appears in Terraform `allowed_origins`, then apply.
- Upload signature mismatch: the `Content-Type` sent to S3 must match the signed content type.
- Lambda import error: rebuild packages with `scripts/package-lambdas.sh`; Pillow must be compiled for Linux x86_64.
- Result remains processing: inspect Lambda errors and confirm the S3 notification exists on the source bucket.
- Domain does not resolve: confirm the registrar uses the name servers assigned to the `cloudwithliz.space` Route 53 hosted zone, then inspect the Terraform-managed A and AAAA alias records.
- Certificate remains pending: inspect the ACM validation CNAME records in Route 53; the certificate must be in `us-east-1` for CloudFront.

## Useful commands

```bash
aws logs tail /aws/lambda/cloud-image-pipeline-dev-processor --follow
aws sqs receive-message --queue-url "$(terraform -chdir=terraform output -raw processing_dlq_url)"
aws s3 ls "s3://$(terraform -chdir=terraform output -raw processed_bucket)/thumbnails/"
```
