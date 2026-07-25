import importlib
import io
import sys
from unittest.mock import MagicMock

from PIL import Image


def test_processes_image(monkeypatch):
    image_bytes = io.BytesIO()
    Image.new("RGB", (1200, 800), "blue").save(image_bytes, "JPEG")
    client = MagicMock()
    client.get_object.return_value = {"Body": io.BytesIO(image_bytes.getvalue())}
    boto = MagicMock()
    boto.client.return_value = client
    monkeypatch.setitem(sys.modules, "boto3", boto)
    sys.modules.pop("src.processor.handler", None)
    module = importlib.import_module("src.processor.handler")
    record = {"s3": {"bucket": {"name": "source"}, "object": {"key": "abc.jpg", "size": 1000}}}
    assert module.process_record(record) == "thumbnails/abc.webp"
    kwargs = client.put_object.call_args.kwargs
    assert kwargs["Bucket"] == "processed-bucket"
    assert kwargs["ContentType"] == "image/webp"

