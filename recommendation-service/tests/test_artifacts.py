from __future__ import annotations

import torch

from app.config import Settings
from app.data.mapping import build_mappings
from app.model_registry import ModelRegistry, load_artifact_directory
from app.recommenders.mbmf import MultiBehaviorMF
from training.artifacts import save_artifact, update_benchmark_pointer
from training.config import TrainConfig


def test_artifact_round_trip_preserves_scores(
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
    model = MultiBehaviorMF(users=4, items=6, embedding_dimension=8)
    model.eval()
    users = torch.tensor([0, 1])
    before = model.all_item_preference_scores(users).detach()

    artifact = save_artifact(
        artifact_root=tmp_path / "artifacts",
        model_version="mbmf_test",
        model=model,
        config=config,
        mappings=mappings,
        fit_interactions=synthetic_interactions,
        items=synthetic_items,
        genre_names=["Action", "Comedy"],
        metrics={"test": {"ndcg@10": 0.2}},
        history=[{"epoch": 1, "train_loss": 1.0}],
        metadata={
            "modelVersion": "mbmf_test",
            "source": "MOVIELENS",
            "deployable": False,
        },
    )
    loaded = load_artifact_directory(artifact)
    after = loaded.model.all_item_preference_scores(users).detach()

    assert not (tmp_path / "artifacts/benchmark-latest.json").exists()
    pointer = update_benchmark_pointer(tmp_path / "artifacts", "mbmf_test")
    assert torch.allclose(before, after, atol=1e-7)
    assert loaded.mappings.item_to_index == mappings.item_to_index
    assert loaded.seen_items(0).size > 0
    assert pointer.is_file()
    assert (artifact / "item_popularity.json").is_file()

    production_registry = ModelRegistry(
        Settings(
            app_env="production",
            allow_benchmark_model=True,
            model_storage_path=tmp_path / "artifacts",
            model_version="mbmf_test",
        )
    )
    production_registry.load()
    assert production_registry.loaded is None
    assert "deployable=false" in str(production_registry.load_error)
