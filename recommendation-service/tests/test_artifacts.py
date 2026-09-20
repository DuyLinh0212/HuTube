from __future__ import annotations

from app.config import Settings
from app.data.mapping import build_mappings
from app.model_registry import ModelRegistry, load_artifact_directory
from app.recommenders.item_cf import ItemBasedCF
from app.recommenders.user_cf import UserBasedCF
from training.artifacts import save_artifact, update_benchmark_pointer
from training.config import TrainConfig


def test_artifact_round_trip_preserves_recommendations(
    tmp_path,
    synthetic_interactions,
    synthetic_items,
) -> None:
    config = TrainConfig.model_validate(
        {
            "project_root": tmp_path,
            "data": {
                "path": "unused",
                "strict_counts": False,
                "processed_path": "processed.csv",
            },
        }
    )
    mappings = build_mappings(
        synthetic_interactions,
        item_ids=synthetic_items["item_id"].tolist(),
    )
    models = {
        "user_based": UserBasedCF.fit(
            synthetic_interactions,
            user_count=len(mappings.user_to_index),
            item_count=len(mappings.item_to_index),
            neighbor_count=3,
            interaction_mode="rating",
        ),
        "item_based": ItemBasedCF.fit(
            synthetic_interactions,
            user_count=len(mappings.user_to_index),
            item_count=len(mappings.item_to_index),
            neighbor_count=3,
            interaction_mode="rating",
        ),
    }
    before = models["item_based"].recommend(0, limit=3)
    artifact = save_artifact(
        artifact_root=tmp_path / "artifacts",
        model_version="cf_test",
        models=models,
        config=config,
        mappings=mappings,
        fit_interactions=synthetic_interactions,
        items=synthetic_items,
        genre_names=["Action", "Comedy"],
        metrics={
            "models": {
                "user_based": {"preference": {"preference_alignment@10": 0.2}},
                "item_based": {"preference": {"preference_alignment@10": 0.3}},
            }
        },
        history=[{"model": "item_based", "fit_seconds": 0.01}],
        metadata={
            "modelVersion": "cf_test",
            "source": "MOVIELENS",
            "deployable": False,
            "modelTypes": ["user_based", "item_based"],
        },
    )
    loaded = load_artifact_directory(artifact, model_type="item_based")
    after = loaded.model.recommend(0, limit=3)

    assert before == after
    assert loaded.mappings.item_to_index == mappings.item_to_index
    assert loaded.seen_items(0).size > 0
    assert (artifact / "user_based.npz").is_file()
    assert (artifact / "item_based.npz").is_file()
    assert not (artifact / "model.pt").exists()
    assert not (artifact / "item_popularity.json").exists()

    pointer = update_benchmark_pointer(tmp_path / "artifacts", "cf_test")
    assert pointer.is_file()

    production_registry = ModelRegistry(
        Settings(
            app_env="production",
            allow_benchmark_model=True,
            model_storage_path=tmp_path / "artifacts",
            model_version="cf_test",
        )
    )
    production_registry.load()
    assert production_registry.loaded is None
    assert "deployable=false" in str(production_registry.load_error)
