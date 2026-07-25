#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
API_ENDPOINT="$(terraform -chdir="$ROOT/terraform" output -raw api_endpoint)"
FRONTEND_BUCKET="$(terraform -chdir="$ROOT/terraform" output -raw frontend_bucket)"
DISTRIBUTION_ID="$(terraform -chdir="$ROOT/terraform" output -raw cloudfront_distribution_id)"

rm -rf "$ROOT/dist"
mkdir -p "$ROOT/dist"
cp "$ROOT/frontend/index.html" "$ROOT/frontend/styles.css" "$ROOT/frontend/app.js" "$ROOT/dist/"
printf 'window.APP_CONFIG = { apiEndpoint: "%s" };\n' "$API_ENDPOINT" > "$ROOT/dist/config.js"

aws s3 cp "$ROOT/dist/app.js" "s3://$FRONTEND_BUCKET/app.js" \
  --content-type "application/javascript; charset=utf-8" --cache-control "public, max-age=300" --only-show-errors
aws s3 cp "$ROOT/dist/styles.css" "s3://$FRONTEND_BUCKET/styles.css" \
  --content-type "text/css; charset=utf-8" --cache-control "public, max-age=300" --only-show-errors
aws s3 cp "$ROOT/dist/index.html" "s3://$FRONTEND_BUCKET/index.html" \
  --content-type "text/html; charset=utf-8" --cache-control "no-cache" --only-show-errors
aws s3 cp "$ROOT/dist/config.js" "s3://$FRONTEND_BUCKET/config.js" \
  --content-type "application/javascript; charset=utf-8" --cache-control "no-store" --only-show-errors

aws cloudfront create-invalidation --distribution-id "$DISTRIBUTION_ID" --paths "/*" >/dev/null
echo "Frontend deployed to $(terraform -chdir="$ROOT/terraform" output -raw application_url)"

