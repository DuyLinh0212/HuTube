"""Private R2 objects used by the deployed collaborative-filter model."""

from __future__ import annotations

import json
import time
from typing import Any
from uuid import uuid4

import boto3
from botocore.exceptions import ClientError

from app.config import Settings


class R2ConfigurationError(RuntimeError):
    def __init__(self, missing_settings: list[str]) -> None:
        self.missing_settings = missing_settings
        super().__init__(
            "Recommendation Service is missing R2 settings: " + ", ".join(missing_settings)
        )


class R2Store:
    def __init__(self, settings: Settings) -> None:
        if settings.missing_r2_settings:
            raise R2ConfigurationError(settings.missing_r2_settings)
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

    def read_versioned_json(self, key: str) -> tuple[dict | None, str | None]:
        try:
            response = self.client.get_object(Bucket=self.bucket, Key=key)
            return json.loads(response["Body"].read()), response["ETag"]
        except ClientError as exc:
            if exc.response.get("Error", {}).get("Code") in {"NoSuchKey", "404"}:
                return None, None
            raise

    def list_keys(self, prefix: str) -> list[str]:
        pages = self.client.get_paginator("list_objects_v2").paginate(
            Bucket=self.bucket, Prefix=prefix,
        )
        return [item["Key"] for page in pages for item in page.get("Contents", [])
                if item["Key"].endswith(".json")]

    def compare_write_json(self, key: str, value: dict, etag: str | None) -> str:
        response = self.client.put_object(
            Bucket=self.bucket, Key=key, Body=json.dumps(value).encode(),
            ContentType="application/json", **({"IfMatch": etag} if etag else {"IfNoneMatch": "*"}),
        )
        return response["ETag"]

    def acquire_training_lease(self) -> tuple[str, str]:
        value, etag = self.read_versioned_json("collaborative_cf/training-lease.json")
        if value and value["expiresAt"] > time.time():
            raise RuntimeError("Another replica is training the model.")
        owner = str(uuid4())
        version = self.compare_write_json("collaborative_cf/training-lease.json",
                                          {"owner": owner, "expiresAt": time.time() + 1800}, etag)
        return owner, version

    def renew_training_lease(self, owner: str, version: str) -> str:
        return self.compare_write_json("collaborative_cf/training-lease.json",
                                       {"owner": owner, "expiresAt": time.time() + 1800}, version)

    def release_training_lease(self, owner: str, version: str) -> None:
        self.compare_write_json(
            "collaborative_cf/training-lease.json",
            {"owner": owner, "expiresAt": 0},
            version,
        )
