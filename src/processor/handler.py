import io
import json
import logging
import os
from urllib.parse import unquote_plus

import boto3
from PIL import Image, ImageOps, UnidentifiedImageError

logger = logging.getLogger()
logger.setLevel(logging.INFO)

s3 = boto3.client("s3")
PROCESSED_BUCKET = os.environ.get("PROCESSED_BUCKET", "processed-bucket")
THUMBNAIL_SIZE = int(os.environ.get("THUMBNAIL_SIZE", "512"))
MAX_SOURCE_BYTES = int(os.environ.get("MAX_SOURCE_BYTES", 10 * 1024 * 1024))


def process_record(record):
    source_bucket = record["s3"]["bucket"]["name"]
    source_key = unquote_plus(record["s3"]["object"]["key"])
    event_size = int(record["s3"]["object"].get("size", 0))
    if event_size > MAX_SOURCE_BYTES:
        raise ValueError(f"Object exceeds {MAX_SOURCE_BYTES} byte processing limit")

    result = s3.get_object(Bucket=source_bucket, Key=source_key)
    payload = result["Body"].read(MAX_SOURCE_BYTES + 1)
    if len(payload) > MAX_SOURCE_BYTES:
        raise ValueError(f"Object exceeds {MAX_SOURCE_BYTES} byte processing limit")

    try:
        with Image.open(io.BytesIO(payload)) as original:
            image = ImageOps.exif_transpose(original)
            image.thumbnail((THUMBNAIL_SIZE, THUMBNAIL_SIZE), Image.Resampling.LANCZOS)
            if image.mode not in ("RGB", "RGBA"):
                image = image.convert("RGBA" if "transparency" in image.info else "RGB")
            output = io.BytesIO()
            image.save(output, format="WEBP", quality=82, method=6)
    except (UnidentifiedImageError, OSError) as error:
        raise ValueError("Uploaded object is not a supported image") from error

    destination_key = f"thumbnails/{source_key.rsplit('.', 1)[0]}.webp"
    s3.put_object(
        Bucket=PROCESSED_BUCKET,
        Key=destination_key,
        Body=output.getvalue(),
        ContentType="image/webp",
        CacheControl="public, max-age=31536000, immutable",
        Metadata={"source-key": source_key},
    )
    logger.info(json.dumps({"event": "image_processed", "source_key": source_key, "destination_key": destination_key}))
    return destination_key


def handler(event, context):
    failures = []
    for record in event.get("Records", []):
        try:
            process_record(record)
        except Exception:
            logger.exception(json.dumps({"event": "processing_failed", "request_id": context.aws_request_id}))
            failures.append(record.get("responseElements", {}).get("x-amz-request-id", "unknown"))
    if failures:
        raise RuntimeError(f"Failed to process {len(failures)} record(s)")
    return {"processed": len(event.get("Records", []))}

