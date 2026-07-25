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

