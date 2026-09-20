from __future__ import annotations

import numpy as np

from app.recommenders.similarity import jaccard_similarity, pearson_similarity
from training.trainer import fit_all_models


def test_pearson_uses_rating_direction_and_not_missing_zeroes() -> None:
    matrix = np.asarray(
        [
            [1.0, 2.0, 3.0, 0.0],
            [1.0, 2.0, 3.0, 0.0],
            [3.0, 2.0, 1.0, 0.0],
        ],
        dtype=np.float32,
    )

    similarity = pearson_similarity(matrix)

    assert similarity[0, 1] > 0.99
    assert similarity[0, 2] < -0.99
    assert similarity[0, 0] == 0.0


def test_jaccard_uses_presence_not_rating_magnitude() -> None:
    matrix = np.asarray(
            [[5.0, 1.0, 0.0], [1.0, 0.0, 5.0]],
        dtype=np.float32,
    )

    similarity = jaccard_similarity(matrix)

    assert similarity[0, 1] == 1.0 / 3.0


def test_fit_all_models_creates_user_and_item_variants(
    tmp_path,
    synthetic_interactions,
    synthetic_items,
) -> None:
    from app.data.mapping import build_mappings
    from training.config import TrainConfig

    config = TrainConfig.model_validate(
        {
            "project_root": tmp_path,
            "data": {
                "path": "unused",
                "strict_counts": False,
                "processed_path": "processed.csv",
            },
            "model": {
                "similarities": ["cosine", "jaccard", "pearson"],
                "interaction_mode": "rating",
                "neighbor_count": 3,
            },
        }
    )
    mappings = build_mappings(
        synthetic_interactions,
        item_ids=synthetic_items["item_id"].tolist(),
    )

    fitted = fit_all_models(
        synthetic_interactions,
        config=config,
        mappings=mappings,
    )

    assert set(fitted) == {
        "user_based_cosine",
        "user_based_jaccard",
        "user_based_pearson",
        "item_based_cosine",
        "item_based_jaccard",
        "item_based_pearson",
    }
