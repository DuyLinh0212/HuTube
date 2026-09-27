from __future__ import annotations

import hashlib
import json
import time

from fastapi.testclient import TestClient

from app.config import Settings
from app.main import create_app
from app.model_registry import ModelRegistry


class FakeR2:
    def __init__(self) -> None:
        self.objects: dict[str, bytes] = {}

    def read(self, key: str) -> bytes:
        return self.objects[key]

    def read_optional(self, key: str) -> bytes | None:
        return self.objects.get(key)

    def write(self, key: str, content: bytes, content_type: str) -> None:
        self.objects[key] = content

    def read_json(self, key: str) -> dict | None:
        raw = self.read_optional(key)
        return json.loads(raw) if raw is not None else None

    def write_json(self, key: str, value: dict) -> None:
        self.write(key, json.dumps(value).encode(), "application/json")


def test_r2_training_restart_and_failed_update_keep_active_model(tmp_path, monkeypatch) -> None:
    store = FakeR2()
    monkeypatch.setattr("app.model_registry.R2Store", lambda _: store)
    settings = Settings(model_storage_path=tmp_path, app_env="production",
                        recommender_service_token="infer-secret",
                        recommender_admin_token="admin-secret",
                        r2_account_id="test", r2_access_key_id="test",
                        r2_secret_access_key="test", r2_bucket_name="test")
    csv_key = "collaborative_cf/2026/09/26/interactions_test.csv"
    csv = (b"user_id,video_id,score\n"
           b"u1,v1,5\nu1,v2,4\nu2,v1,4\nu2,v3,5\nu3,v2,5\nu3,v3,4\n")
    store.write(csv_key, csv, "text/csv")
    digest = hashlib.sha256(csv).hexdigest()
    registry = ModelRegistry(settings)
    with TestClient(create_app(settings, registry)) as client:
        assert client.post(
            "/internal/model/train", json={"csvKey": csv_key, "csvSha256": digest}
        ).status_code == 401
        started = client.post(
            "/internal/model/train",
            headers={"X-Model-Admin-Token": "admin-secret"},
            json={"csvKey": csv_key, "csvSha256": digest},
        )
        assert started.status_code == 202
        job_id = started.json()["jobId"]
        for _ in range(100):
            progress = client.get(f"/internal/model/jobs/{job_id}",
                                  headers={"X-Model-Admin-Token": "admin-secret"}).json()
            if progress["status"] != "running":
                break
            time.sleep(.05)
        assert progress["status"] == "completed", progress
        manifest = store.read_json("collaborative_cf/active.json")
        assert manifest is not None
        assert manifest["csvKey"] == csv_key
        assert manifest["csvSha256"] == digest
        assert manifest["artifactKey"] in store.objects
        response = client.post(
            "/internal/recommendations",
            headers={"X-Service-Token": "infer-secret"},
            json={"userId": "u1", "limit": 10, "excludeItemIds": []},
        )
        assert response.status_code == 200
        assert [item["itemId"] for item in response.json()["items"]] == ["v3"]

        invalid_key = "collaborative_cf/2026/09/26/invalid.csv"
        invalid = b"user_id,video_id,score\n"
        store.write(invalid_key, invalid, "text/csv")
        bad = client.post(
            "/internal/model/train",
            headers={"X-Model-Admin-Token": "admin-secret"},
            json={"csvKey": invalid_key, "csvSha256": hashlib.sha256(invalid).hexdigest()},
        )
        assert bad.status_code == 202
        for _ in range(100):
            failed = client.get(f"/internal/model/jobs/{bad.json()['jobId']}",
                                headers={"X-Model-Admin-Token": "admin-secret"}).json()
            if failed["status"] != "running":
                break
            time.sleep(.05)
        assert failed["status"] == "failed"
        assert store.read_json("collaborative_cf/active.json") == manifest
        assert registry.loaded is not None
        assert registry.loaded.metadata["modelVersion"] == manifest["modelVersion"]

    restarted = ModelRegistry(settings)
    restarted.load()
    assert restarted.loaded is not None
    assert restarted.loaded.metadata["modelVersion"] == manifest["modelVersion"]
