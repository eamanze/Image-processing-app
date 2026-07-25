#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
rm -rf "$ROOT/build"
mkdir -p "$ROOT/build/presign" "$ROOT/build/processor"
cp "$ROOT/src/presign/handler.py" "$ROOT/build/presign/handler.py"
cp "$ROOT/src/processor/handler.py" "$ROOT/build/processor/handler.py"
docker run --rm --platform linux/amd64 \
  -v "$ROOT:/var/task" -w /var/task public.ecr.aws/sam/build-python3.12:latest \
  pip install -r src/processor/requirements.txt -t build/processor --no-cache-dir
(cd "$ROOT/build/presign" && zip -qr ../presign.zip .)
(cd "$ROOT/build/processor" && zip -qr ../processor.zip .)
echo "Created build/presign.zip and build/processor.zip"

