from __future__ import annotations

import numpy as np
import pandas as pd

from app.data.mapping import IndexMappings
from app.recommenders.item_cf import ItemBasedCF
from training.evaluate import evaluate_model


def test_item_cf_predicts_and_excludes_seen_items(
    synthetic_interactions: pd.DataFrame,
    synthetic_items: pd.DataFrame,
) -> None:
    mappings = IndexMappings(
        user_to_index={str(index + 1): index for index in range(4)},
        item_to_index={str(index + 1): index for index in range(6)},
    )
    model = ItemBasedCF.fit(
        synthetic_interactions,
        user_count=4,
        item_count=6,
        neighbor_count=3,
        interaction_mode="binary",
    )

    predictions = model.predict_pairs(
        np.asarray([0, 1, 2]),
        np.asarray([3, 4, 5]),
    )
    recommendations = model.recommend(0, limit=3)
    seen = set(int(value) for value in model.seen_items(0))
    result = evaluate_model(
        model,
        synthetic_interactions,
        mappings=mappings,
        items=synthetic_items,
        genre_names=["Action", "Comedy"],
        k_values=[2],
        positive_rating_threshold=4.0,
    )

    assert predictions.shape == (3,)
    assert np.isfinite(predictions).all()
    assert all(item not in seen for item, _score in recommendations)
    assert 0.0 <= result.metrics["preference_alignment@2"] <= 1.0
