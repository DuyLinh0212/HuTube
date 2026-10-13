from __future__ import annotations

from uuid import uuid4

import pytest
from fastapi.testclient import TestClient

from app.config import Settings
from app.main import create_app
from app.model_registry import ModelRegistry


def _settings(tmp_path, **overrides):
    return Settings(_env_file=None, app_env="production", model_storage_path=tmp_path,
                    recommender_admin_token="admin-test", r2_account_id="",
                    r2_access_key_id="", r2_secret_access_key="", r2_bucket_name="",
                    **overrides)


@pytest.mark.parametrize("with_job_id", [False, True])
def test_training_reports_missing_r2_configuration(tmp_path, with_job_id):
    settings = _settings(tmp_path)
    payload = {"csvKey": "collaborative_cf/test.csv", "csvSha256": "a" * 64}
    if with_job_id:
        payload["jobId"] = str(uuid4())
    with TestClient(create_app(settings)) as client:
        rejected = client.post("/internal/model/train", json=payload)
        assert rejected.status_code == 401
        response = client.post("/internal/model/train", json=payload,
                               headers={"X-Model-Admin-Token": "admin-test"})
        assert response.status_code == 503
        detail = response.json()["detail"]
        assert detail["code"] == "MODEL_STORAGE_NOT_CONFIGURED"
        assert detail["retryable"] is False
        assert detail["missingSettings"] == settings.missing_r2_settings
        assert "Recommendation Service in Render" in detail["message"]


def test_model_status_reports_missing_settings_without_secret_values(tmp_path):
    settings = _settings(tmp_path)
    with TestClient(create_app(settings)) as client:
        response = client.get("/internal/model",
                              headers={"X-Model-Admin-Token": "admin-test"})
        assert response.status_code == 200
        assert response.json()["storageConfigured"] is False
        assert response.json()["missingStorageSettings"] == settings.missing_r2_settings
        assert "admin-test" not in response.text
        progress = client.get(f"/internal/model/jobs/{uuid4()}",
                              headers={"X-Model-Admin-Token": "admin-test"})
        assert progress.status_code == 503
        assert progress.json()["detail"]["code"] == "MODEL_STORAGE_NOT_CONFIGURED"


def test_dotnet_r2_environment_aliases(monkeypatch):
    pairs = {
        "R2_ACCOUNT_ID": ("Storage__R2__AccountId", "test-account"),
        "R2_ACCESS_KEY_ID": ("Storage__R2__AccessKeyId", "test-access"),
        "R2_SECRET_ACCESS_KEY": ("Storage__R2__SecretAccessKey", "test-secret"),
        "R2_BUCKET_NAME": ("Storage__R2__BucketName", "test-bucket"),
    }
    for name, (alias, value) in pairs.items():
        monkeypatch.delenv(name, raising=False)
        monkeypatch.setenv(alias, value)
    settings = Settings(_env_file=None)
    assert settings.r2_account_id == "test-account"
    assert settings.r2_access_key_id == "test-access"
    assert settings.r2_secret_access_key == "test-secret"
    assert settings.r2_bucket_name == "test-bucket"
    assert settings.missing_r2_settings == []
    monkeypatch.setenv("R2_ACCOUNT_ID", "explicit-account")
    assert Settings(_env_file=None).r2_account_id == "explicit-account"


def test_unexpected_training_error_is_logged_and_redacted(tmp_path, monkeypatch, caplog):
    settings = _settings(tmp_path)
    registry = ModelRegistry(settings)

    def fail(_):
        raise RuntimeError("private-storage-secret")

    monkeypatch.setattr(registry, "get_job", fail)
    with TestClient(create_app(settings, registry), raise_server_exceptions=False) as client:
        response = client.post("/internal/model/train", json={
            "jobId": str(uuid4()), "csvKey": "collaborative_cf/test.csv", "csvSha256": "a" * 64,
        }, headers={"X-Model-Admin-Token": "admin-test"})
        assert response.status_code == 500
        assert response.json()["detail"]["code"] == "MODEL_SERVICE_ERROR"
        assert response.json()["detail"]["errorType"] == "RuntimeError"
        assert "private-storage-secret" not in response.text
        assert any(record.exc_info for record in caplog.records)
