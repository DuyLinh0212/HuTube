from __future__ import annotations

import pandas as pd
from fastapi.testclient import TestClient

from app.config import Settings
from app.data.mapping import build_mappings, build_seen_csr, encode_interactions
from app.main import create_app
from app.model_registry import LoadedModel, ModelRegistry
from app.recommenders.item_cf import ItemBasedCF


def _client(tmp_path) -> TestClient:
    interactions = pd.DataFrame(
        [
            {"user_id": "u1", "item_id": "i1", "rating": 5.0},
            {"user_id": "u1", "item_id": "i2", "rating": 4.0},
            {"user_id": "u2", "item_id": "i2", "rating": 5.0},
            {"user_id": "u2", "item_id": "i3", "rating": 4.0},
        ]
    )
    mappings = build_mappings(interactions, item_ids=["i1", "i2", "i3", "i4"])
    encoded = encode_interactions(interactions, mappings)
    model = ItemBasedCF.fit(
        encoded,
        user_count=len(mappings.user_to_index),
        item_count=len(mappings.item_to_index),
        neighbor_count=2,
        interaction_mode="rating",
    )
    indptr, indices = build_seen_csr(encoded, mappings)
    settings = Settings(
        recommender_service_token="test-token",
        allow_benchmark_model=True,
        model_storage_path=tmp_path,
        model_type="item_based",
    )
    registry = ModelRegistry(settings)
    registry.loaded = LoadedModel(
        model=model,
        model_type="item_based",
        mappings=mappings,
        index_to_item=mappings.index_to_item,
        seen_indptr=indptr,
        seen_indices=indices,
        metadata={
            "modelVersion": "test-v1",
            "source": "MOVIELENS",
            "deployable": False,
        },
        item_metadata={},
        artifact_dir=tmp_path,
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
            json={"userId": "u1", "limit": 3, "excludeItemIds": ["i3"]},
        )

    assert unauthorized.status_code == 401
    assert response.status_code == 200
    assert response.json()["source"] == "MOVIELENS"
    item_ids = {item["itemId"] for item in response.json()["items"]}
    assert "i1" not in item_ids
    assert "i2" not in item_ids
    assert "i3" not in item_ids


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
