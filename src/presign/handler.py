import base64
import json
import logging
import os
import re
import uuid

import boto3

logger = logging.getLogger()
logger.setLevel(logging.INFO)

s3 = boto3.client("s3")
SOURCE_BUCKET = os.environ.get("SOURCE_BUCKET", "source-bucket")
PROCESSED_BUCKET = os.environ.get("PROCESSED_BUCKET", "processed-bucket")
MAX_UPLOAD_BYTES = int(os.environ.get("MAX_UPLOAD_BYTES", 10 * 1024 * 1024))
ALLOWED_TYPES = {"image/jpeg": "jpg", "image/png": "png", "image/webp": "webp"}
KEY_PATTERN = re.compile(r"^[0-9a-f-]{36}\.(?:jpg|png|webp)$")


def response(status, body):
    return {
        "statusCode": status,
        "headers": {"content-type": "application/json"},
        "body": json.dumps(body),
    }


def parse_body(event):
    raw = event.get("body") or "{}"
    if event.get("isBase64Encoded"):
        raw = base64.b64decode(raw).decode("utf-8")
    return json.loads(raw)


def handler(event, _context):
    request_id = event.get("requestContext", {}).get("requestId", "unknown")
    method = event.get("requestContext", {}).get("http", {}).get("method", "")
    route_key = event.get("routeKey", "")
    logger.info(json.dumps({"event": "request_received", "request_id": request_id, "route": route_key}))

    try:
        if method == "POST" and route_key == "POST /uploads":
            body = parse_body(event)
            content_type = body.get("contentType", "")
            size = body.get("size", 0)
            if content_type not in ALLOWED_TYPES:
                return response(400, {"message": "Only JPEG, PNG, and WebP images are allowed"})
            if not isinstance(size, int) or size < 1 or size > MAX_UPLOAD_BYTES:
                return response(400, {"message": f"Image must be between 1 and {MAX_UPLOAD_BYTES} bytes"})

            key = f"{uuid.uuid4()}.{ALLOWED_TYPES[content_type]}"
            url = s3.generate_presigned_url(
                "put_object",
                Params={"Bucket": SOURCE_BUCKET, "Key": key, "ContentType": content_type},
                ExpiresIn=300,
            )
            return response(201, {"key": key, "uploadUrl": url, "expiresIn": 300})

        if method == "GET" and route_key == "GET /images/{key}":
            key = event.get("pathParameters", {}).get("key", "")
            if not KEY_PATTERN.fullmatch(key):
                return response(400, {"message": "Invalid image key"})
            processed_key = f"thumbnails/{key.rsplit('.', 1)[0]}.webp"
            try:
                s3.head_object(Bucket=PROCESSED_BUCKET, Key=processed_key)
            except s3.exceptions.ClientError as error:
                if error.response.get("ResponseMetadata", {}).get("HTTPStatusCode") == 404:
                    return response(202, {"status": "processing"})
                raise
            image_url = s3.generate_presigned_url(
                "get_object", Params={"Bucket": PROCESSED_BUCKET, "Key": processed_key}, ExpiresIn=300
            )
            download_url = s3.generate_presigned_url(
                "get_object",
                Params={
                    "Bucket": PROCESSED_BUCKET,
                    "Key": processed_key,
                    "ResponseContentDisposition": f'attachment; filename="{key.rsplit(".", 1)[0]}.webp"',
                    "ResponseContentType": "image/webp",
                },
                ExpiresIn=300,
            )
            return response(
                200,
                {
                    "status": "ready",
                    "imageUrl": image_url,
                    "downloadUrl": download_url,
                    "expiresIn": 300,
                },
            )
    except (json.JSONDecodeError, UnicodeDecodeError):
        return response(400, {"message": "Request body must be valid JSON"})
    except Exception:
        logger.exception(json.dumps({"event": "request_failed", "request_id": request_id}))
        return response(500, {"message": "Internal server error"})

    return response(404, {"message": "Route not found"})
