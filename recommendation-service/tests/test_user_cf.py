from __future__ import annotations

import pandas as pd

from app.data.mapping import build_mappings, encode_interactions
from app.recommenders.user_cf import UserBasedCF


def _example() -> pd.DataFrame:
    frame = pd.DataFrame(
        [
            {"user_id": "A", "item_id": "1", "rating": 1.0},
            {"user_id": "A", "item_id": "2", "rating": 1.0},
            {"user_id": "A", "item_id": "3", "rating": 1.0},
            {"user_id": "B", "item_id": "3", "rating": 1.0},
            {"user_id": "B", "item_id": "5", "rating": 1.0},
            {"user_id": "B", "item_id": "6", "rating": 1.0},
            {"user_id": "C", "item_id": "2", "rating": 1.0},
            {"user_id": "C", "item_id": "3", "rating": 1.0},
            {"user_id": "C", "item_id": "4", "rating": 1.0},
        ]
    )
    frame["timestamp"] = pd.Timestamp("2024-01-01", tz="UTC")
    for column in ("like", "dislike", "comment", "share", "watch_ratio"):
        frame[column] = None
    frame["source"] = "MOVIELENS"
    mappings = build_mappings(frame)
    return encode_interactions(frame, mappings)


def test_user_cf_recommends_from_similar_users() -> None:
    interactions = _example()
    model = UserBasedCF.fit(
        interactions,
        user_count=3,
        item_count=6,
        neighbor_count=2,
        interaction_mode="binary",
    )
    user_c = model.recommend(2, limit=3)
    recommended_ids = [item_index + 1 for item_index, _score in user_c]

    assert recommended_ids[0] == 1
    assert set(recommended_ids[1:]) == {5, 6}
    assert np_is_close(model.similarities[2, 0], 2 / 3)
    assert np_is_close(model.similarities[2, 1], 1 / 3)


def np_is_close(left: float, right: float) -> bool:
    return abs(float(left) - float(right)) < 1e-6
