from __future__ import annotations

import hashlib
from datetime import UTC, datetime

from botocore.exceptions import ClientError
from fastapi.testclient import TestClient

from app.config import Settings
from app.main import create_app
from app.model_registry import ModelRegistry
from app.model_statistics import ModelStatistics
from tests.test_r2_update import FakeR2


def _settings(tmp_path):
    return Settings(model_storage_path=tmp_path, app_env="production",
                    recommender_service_token="infer-secret",
                    recommender_admin_token="admin-secret",
                    r2_account_id="test", r2_access_key_id="test",
                    r2_secret_access_key="test", r2_bucket_name="test")


def test_catalog_tracks_builds_successful_usage_and_restart(tmp_path, monkeypatch):
    store = FakeR2()
    monkeypatch.setattr("app.model_registry.R2Store", lambda _: store)
    monkeypatch.setattr("app.model_statistics.R2Store", lambda _: store)
    settings = _settings(tmp_path)
    registry = ModelRegistry(settings)
    key = "collaborative_cf/interactions_test.csv"
    csv = b"user_id,video_id,score\nu1,v1,1\nu1,v2,.8\nu2,v1,.8\nu2,v3,1\n"
    store.write(key, csv, "text/csv")
    first = registry.train_from_r2(key, hashlib.sha256(csv).hexdigest())

    with TestClient(create_app(settings, registry)) as client:
        for headers in ({}, {"X-Service-Token": "infer-secret"},
                        {"X-Model-Admin-Token": "wrong"}):
            assert client.get("/internal/models", headers=headers).status_code == 401
        headers = {"X-Model-Admin-Token": "admin-secret"}
        initial = client.get("/internal/models", headers=headers).json()["items"][0]
        assert initial["lastUsedAt"] is None
        assert initial["buildDurationSeconds"] >= initial["fitDurationSeconds"] >= 0
        assert initial["usersCount"] == 2
        assert initial["videosCount"] == 3
        assert initial["interactionsCount"] == 4
        assert initial["isActive"] is True
        # Failed inference and unauthorized calls must not count as use.
        assert client.post("/internal/recommendations", json={"userId": "u1"}).status_code == 401
        assert client.post("/internal/recommendations", headers={"X-Service-Token": "infer-secret"},
                           json={"userId": "missing"}).status_code == 404
        unchanged = client.get("/internal/models", headers=headers).json()["items"][0]
        assert unchanged["lastUsedAt"] is None
        assert client.post("/internal/recommendations", headers={"X-Service-Token": "infer-secret"},
                           json={"userId": "u1"}).status_code == 200
        used_at = client.get("/internal/models", headers=headers).json()["items"][0]["lastUsedAt"]
        assert datetime.fromisoformat(used_at) <= datetime.now(UTC)
        registry.statistics.flush()
        second = registry.train_from_r2(key, hashlib.sha256(csv).hexdigest(),
                                        model_algorithm="batch_incremental_partial_topk")

    restarted = ModelRegistry(settings)
    restarted.load()
    items = restarted.statistics.catalog(restarted.manifest, restarted.loaded.metadata)["items"]
    assert len(items) == 2
    assert items[0]["modelVersion"] == second["modelVersion"]
    assert items[0]["isActive"] is True
    assert items[0]["lastUsedAt"] is None
    assert items[1]["modelVersion"] == first["modelVersion"]
    assert items[1]["lastUsedAt"] == used_at
    assert items[1]["isActive"] is False


def test_catalog_recovers_legacy_jobs_without_inventing_statistics(tmp_path, monkeypatch):
    store = FakeR2()
    monkeypatch.setattr("app.model_statistics.R2Store", lambda _: store)
    old = {"modelVersion": "legacy-v1", "modelAlgorithm": "incremental",
           "updatedAt": "2026-10-01T00:00:00Z"}
    store.write_json("collaborative_cf/jobs/old.json", {"jobId": "old", "status": "completed",
                                                     "manifest": old})
    store.write_json("collaborative_cf/active.json", old)
    result = ModelStatistics(_settings(tmp_path)).catalog(old, {"modelVersion": "legacy-v1"})
    assert len(result["items"]) == 1
    item = result["items"][0]
    assert item["buildCompletedAt"] == old["updatedAt"]
    assert item["buildDurationSeconds"] is None
    assert item["usersCount"] is None
    assert item["lastUsedAt"] is None


def test_usage_is_monotonic_across_replicas_and_survives_write_failure(tmp_path, monkeypatch):
    store = FakeR2()
    monkeypatch.setattr("app.model_statistics.R2Store", lambda _: store)
    first, second = ModelStatistics(_settings(tmp_path)), ModelStatistics(_settings(tmp_path))
    key = "collaborative_cf/usage/v1.json"
    first.pending["v1"] = "2026-10-13T12:00:00+00:00"
    second.pending["v1"] = "2026-10-13T11:00:00+00:00"
    first.flush()
    second.flush()
    assert store.read_json(key)["lastUsedAt"] == "2026-10-13T12:00:00+00:00"
    first.pending["v1"] = "2026-10-13T13:00:00+00:00"
    write = store.compare_write_json
    monkeypatch.setattr(store, "compare_write_json", lambda *args: (
        _ for _ in ()).throw(ClientError({"Error": {"Code": "PreconditionFailed"}}, "PutObject")))
    first.flush()
    assert "v1" in first.pending
    monkeypatch.setattr(store, "compare_write_json", write)
    first.flush()
    assert not first.pending
    assert store.read_json(key)["lastUsedAt"] == "2026-10-13T13:00:00+00:00"
