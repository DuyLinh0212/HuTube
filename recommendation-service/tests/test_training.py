from __future__ import annotations

from pathlib import Path

from app.data.mapping import build_mappings
from training.config import TrainConfig
from training.evaluate import evaluate_model
from training.trainer import MODEL_TYPES, fit_both_models


def _config(tmp_path: Path) -> TrainConfig:
    return TrainConfig.model_validate(
        {
            "project_root": tmp_path,
            "data": {
                "path": "unused",
                "strict_counts": False,
                "processed_path": "processed.csv",
            },
            "model": {
                "similarity": "cosine",
                "interaction_mode": "rating",
                "neighbor_count": 3,
            },
            "preference": {"positive_rating_threshold": 4.0},
            "evaluation": {"k": [2, 3]},
        }
    )


def test_both_from_scratch_models_train_and_evaluate(
    tmp_path: Path,
    synthetic_interactions,
    synthetic_items,
) -> None:
    config = _config(tmp_path)
    mappings = build_mappings(
        synthetic_interactions,
        item_ids=synthetic_items["item_id"].tolist(),
    )
    fitted = fit_both_models(synthetic_interactions, config=config, mappings=mappings)

    assert set(fitted) == set(MODEL_TYPES)
    for model_type, result in fitted.items():
        evaluation = evaluate_model(
            result.model,
            synthetic_interactions,
            mappings=mappings,
            items=synthetic_items,
            genre_names=["Action", "Comedy"],
            k_values=[2, 3],
            positive_rating_threshold=4.0,
        )
        assert result.model.model_type == model_type
        assert result.fit_seconds >= 0
        assert 0.0 <= evaluation.metrics["preference_alignment@2"] <= 1.0
        assert 0.0 <= evaluation.metrics["preference_genre_coverage@3"] <= 1.0
        assert 0.0 <= evaluation.metrics["collaborative_support@2"] <= 1.0
        assert 0.0 <= evaluation.metrics["collaborative_evidence_strength@3"] <= 1.0
        assert evaluation.metrics["recommendation_count"] > 0
