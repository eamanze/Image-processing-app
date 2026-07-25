import importlib
import json
import sys
from unittest.mock import MagicMock


def load_handler(monkeypatch):
    client = MagicMock()
    boto = MagicMock()
    boto.client.return_value = client
    monkeypatch.setitem(sys.modules, "boto3", boto)
    sys.modules.pop("src.presign.handler", None)
    return importlib.import_module("src.presign.handler"), client


def test_creates_presigned_upload(monkeypatch):
    module, client = load_handler(monkeypatch)
    client.generate_presigned_url.return_value = "https://signed.example/upload"
    event = {
        "routeKey": "POST /uploads",
        "body": json.dumps({"contentType": "image/jpeg", "size": 100}),
        "requestContext": {"http": {"method": "POST"}, "requestId": "req-1"},
    }
    result = module.handler(event, None)
    body = json.loads(result["body"])
    assert result["statusCode"] == 201
    assert body["uploadUrl"] == "https://signed.example/upload"
    assert body["key"].endswith(".jpg")


def test_rejects_unsupported_content_type(monkeypatch):
    module, _ = load_handler(monkeypatch)
    event = {
        "routeKey": "POST /uploads",
        "body": json.dumps({"contentType": "application/pdf", "size": 100}),
        "requestContext": {"http": {"method": "POST"}},
    }
    assert module.handler(event, None)["statusCode"] == 400


def test_returns_display_and_download_urls_for_processed_image(monkeypatch):
    module, client = load_handler(monkeypatch)
    client.generate_presigned_url.side_effect = [
        "https://signed.example/display",
        "https://signed.example/download",
    ]
    key = "3a778b6e-08a7-49ee-b3a5-20a72411f7d0.jpg"
    event = {
        "routeKey": "GET /images/{key}",
        "pathParameters": {"key": key},
        "requestContext": {"http": {"method": "GET"}, "requestId": "req-2"},
    }

    result = module.handler(event, None)
    body = json.loads(result["body"])

    assert result["statusCode"] == 200
    assert body["imageUrl"] == "https://signed.example/display"
    assert body["downloadUrl"] == "https://signed.example/download"
    download_params = client.generate_presigned_url.call_args_list[1].kwargs["Params"]
    assert download_params["ResponseContentType"] == "image/webp"
    assert download_params["ResponseContentDisposition"] == (
        'attachment; filename="3a778b6e-08a7-49ee-b3a5-20a72411f7d0.webp"'
    )
