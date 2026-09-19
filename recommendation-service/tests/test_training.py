from __future__ import annotations

from pathlib import Path

from app.data.mapping import IndexMappings
from app.data.split import temporal_split
from training.config import TrainConfig
from training.evaluate import _ranking_metrics, evaluate_model
from training.trainer import fit_final_model, train_with_validation


def _config(tmp_path: Path) -> TrainConfig:
    return TrainConfig.model_validate(
        {
            "project_root": tmp_path,
            "data": {
                "path": "unused",
                "strict_counts": False,
                "processed_path": "processed.csv",
                "split": {"train": 0.8, "validation": 0.1, "test": 0.1},
            },
            "model": {"embedding_dimension": 8},
            "training": {
                "seed": 7,
                "learning_rate": 0.01,
                "weight_decay": 0.0,
                "batch_size": 8,
                "max_epochs": 2,
                "device": "cpu",
            },
            "early_stopping": {"enabled": False, "patience": 2, "metric": "ndcg@10"},
            "negative_sampling": {"enabled": True, "negatives_per_positive": 1},
            "evaluation": {"k": [2, 10]},
            "output": {"artifact_root": "artifacts", "report_root": "reports"},
        }
    )


def test_smoke_training_and_evaluation(
    tmp_path: Path,
    synthetic_interactions,
    synthetic_items,
) -> None:
    config = _config(tmp_path)
    split = temporal_split(synthetic_interactions)
    mappings = IndexMappings(
        user_to_index={str(index + 1): index for index in range(4)},
        item_to_index={str(index + 1): index for index in range(6)},
    )
    selection = train_with_validation(
        split.train,
        split.validation,
        config=config,
        mappings=mappings,
        items=synthetic_items,
        genre_names=["Action", "Comedy"],
    )
    final = fit_final_model(
        split.train,
        config=config,
        mappings=mappings,
        items=synthetic_items,
        genre_names=["Action", "Comedy"],
        epochs=selection.best_epoch,
    )
    result = evaluate_model(
        final.model,
        split.test,
        split.train,
        mappings=mappings,
        items=synthetic_items,
        genre_names=["Action", "Comedy"],
        k_values=[2, 10],
        rating_threshold=4.0,
        device=next(final.model.parameters()).device,
    )

    assert selection.history
    assert {"rating", "preference"}.issubset(selection.active_tasks)
    assert result.metrics["rmse"] is not None
    assert 0 <= result.metrics["ndcg@2"] <= 1


def test_ranking_metrics_match_known_example() -> None:
    recommendations = {0: [(3, 0.9), (2, 0.8)]}
    relevant = {0: {2}}

    metrics = _ranking_metrics(recommendations, relevant, k=2)

    assert metrics["precision@2"] == 0.5
    assert metrics["recall@2"] == 1.0
    assert metrics["hitrate@2"] == 1.0
    assert metrics["ndcg@2"] == 1 / 1.584962500721156
    assert all(0.0 <= value <= 1.0 for value in metrics.values())
