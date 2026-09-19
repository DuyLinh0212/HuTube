from __future__ import annotations

import numpy as np
import pandas as pd

from app.data.mapping import IndexMappings
from app.data.split import temporal_split
from app.recommenders.item_cf import ItemBasedCF
from training.item_cf import evaluate_item_cf


def test_item_cf_predicts_and_excludes_seen_items(
    synthetic_interactions: pd.DataFrame,
    synthetic_items: pd.DataFrame,
) -> None:
    split = temporal_split(synthetic_interactions)
    fit = pd.concat([split.train, split.validation], ignore_index=True)
    mappings = IndexMappings(
        user_to_index={str(index + 1): index for index in range(4)},
        item_to_index={str(index + 1): index for index in range(6)},
    )
    model = ItemBasedCF.fit(
        fit,
        user_count=4,
        item_count=6,
        neighbor_count=3,
    )

    predictions = model.predict_pairs(
        split.test["user_index"].to_numpy(dtype=np.int64),
        split.test["item_index"].to_numpy(dtype=np.int64),
    )
    recommendations = model.recommend(0, limit=3)
    seen = set(int(value) for value in model.seen_items(0))
    result = evaluate_item_cf(
        model,
        split.test,
        fit,
        mappings=mappings,
        items=synthetic_items,
        genre_names=["Action", "Comedy"],
        k_values=[2],
        rating_threshold=4.0,
    )

    assert predictions.shape == (len(split.test),)
    assert np.isfinite(predictions).all()
    assert all(item not in seen for item, _score in recommendations)
    assert result.metrics["rmse"] is not None
    assert 0.0 <= result.metrics["ndcg@2"] <= 1.0
