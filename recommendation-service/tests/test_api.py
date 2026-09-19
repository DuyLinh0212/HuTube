from __future__ import annotations

import numpy as np
import torch
from fastapi.testclient import TestClient

from app.config import Settings
from app.data.mapping import IndexMappings
from app.main import create_app
from app.model_registry import LoadedModel, ModelRegistry
from app.recommenders.mbmf import MultiBehaviorMF


def _client(tmp_path) -> TestClient:
    settings = Settings(
        recommender_service_token="test-token",
        allow_benchmark_model=True,
        model_storage_path=tmp_path,
    )
    registry = ModelRegistry(settings)
    model = MultiBehaviorMF(users=2, items=4, embedding_dimension=4)
    model.eval()
    mappings = IndexMappings(
        user_to_index={"u1": 0, "u2": 1},
        item_to_index={"i1": 0, "i2": 1, "i3": 2, "i4": 3},
    )
    registry.loaded = LoadedModel(
        model=model,
        mappings=mappings,
        index_to_item=mappings.index_to_item,
        seen_indptr=np.asarray([0, 1, 1]),
        seen_indices=np.asarray([0]),
        metadata={"modelVersion": "test-v1", "source": "MOVIELENS", "deployable": False},
        item_metadata={},
        artifact_dir=tmp_path,
        device=torch.device("cpu"),
    )
    return TestClient(create_app(settings, registry))


def test_internal_api_requires_token_and_excludes_seen(tmp_path) -> None:
    with _client(tmp_path) as client:
        unauthorized = client.post(
            "/internal/recommendations",
            json={"userId": "u1", "limit": 3, "excludeItemIds": []},
        )
        response = client.post(
            "/internal/recommendations",
            headers={"X-Service-Token": "test-token"},
            json={"userId": "u1", "limit": 3, "excludeItemIds": ["i2"]},
        )

    assert unauthorized.status_code == 401
    assert response.status_code == 200
    item_ids = {item["itemId"] for item in response.json()["items"]}
    assert "i1" not in item_ids
    assert "i2" not in item_ids


def test_unknown_user_returns_404(tmp_path) -> None:
    with _client(tmp_path) as client:
        response = client.post(
            "/internal/recommendations",
            headers={"X-Service-Token": "test-token"},
            json={"userId": "missing", "limit": 3, "excludeItemIds": []},
        )

    assert response.status_code == 404
    assert response.json()["detail"]["code"] == "USER_NOT_IN_MODEL"


def test_invalid_limit_returns_422(tmp_path) -> None:
    with _client(tmp_path) as client:
        response = client.post(
            "/internal/recommendations",
            headers={"X-Service-Token": "test-token"},
            json={"userId": "u1", "limit": 101, "excludeItemIds": []},
        )

    assert response.status_code == 422


def test_no_model_returns_503(tmp_path) -> None:
    settings = Settings(
        recommender_service_token="test-token",
        allow_benchmark_model=True,
        model_storage_path=tmp_path,
    )
    registry = ModelRegistry(settings)
    registry.load_error = "No artifact"
    with TestClient(create_app(settings, registry)) as client:
        response = client.post(
            "/internal/recommendations",
            headers={"X-Service-Token": "test-token"},
            json={"userId": "u1", "limit": 3, "excludeItemIds": []},
        )

    assert response.status_code == 503
    assert response.json()["detail"]["code"] == "MODEL_NOT_READY"
