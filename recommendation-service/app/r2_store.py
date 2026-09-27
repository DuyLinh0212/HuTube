"""Private R2 objects used by the deployed collaborative-filter model."""

from __future__ import annotations

import json
from typing import Any

import boto3
from botocore.exceptions import ClientError

from app.config import Settings


class R2Store:
    def __init__(self, settings: Settings) -> None:
        if not all((settings.r2_account_id, settings.r2_access_key_id,
                    settings.r2_secret_access_key, settings.r2_bucket_name)):
            raise RuntimeError("R2 credentials and bucket must be configured.")
        self.bucket = settings.r2_bucket_name
        self.client = boto3.client(
            "s3",
            endpoint_url=f"https://{settings.r2_account_id}.r2.cloudflarestorage.com",
            aws_access_key_id=settings.r2_access_key_id,
            aws_secret_access_key=settings.r2_secret_access_key,
            region_name="auto",
        )

    def read(self, key: str) -> bytes:
        return self.client.get_object(Bucket=self.bucket, Key=key)["Body"].read()

    def read_optional(self, key: str) -> bytes | None:
        try:
            return self.read(key)
        except ClientError as exc:
            if exc.response.get("Error", {}).get("Code") in {"NoSuchKey", "404"}:
                return None
            raise

    def write(self, key: str, content: bytes, content_type: str) -> None:
        self.client.put_object(Bucket=self.bucket, Key=key, Body=content,
                               ContentType=content_type)

    def read_json(self, key: str) -> dict[str, Any] | None:
        raw = self.read_optional(key)
        return json.loads(raw) if raw is not None else None

    def write_json(self, key: str, value: dict[str, Any]) -> None:
        self.write(key, json.dumps(value, separators=(",", ":")).encode("utf-8"),
                   "application/json")
