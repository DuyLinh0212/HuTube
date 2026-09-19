from __future__ import annotations

from datetime import UTC, datetime, timedelta
from pathlib import Path

import pandas as pd
import pytest

from app.data.mapping import build_mappings, encode_interactions


@pytest.fixture
def synthetic_interactions() -> pd.DataFrame:
    rows = []
    started = datetime(2024, 1, 1, tzinfo=UTC)
    ratings = {
        "1": [5, 4, 3, 2, 5, 1],
        "2": [4, 5, 2, 3, 4, 1],
        "3": [1, 2, 5, 4, 3, 5],
        "4": [2, 1, 4, 5, 3, 4],
    }
    for user_id, user_ratings in ratings.items():
        for offset, rating in enumerate(user_ratings):
            rows.append(
                {
                    "user_id": user_id,
                    "item_id": str(offset + 1),
                    "rating": float(rating),
                    "like": None,
                    "dislike": None,
                    "comment": None,
                    "share": None,
                    "watch_ratio": None,
                    "source": "MOVIELENS",
                    "timestamp": started + timedelta(days=offset),
                }
            )
    frame = pd.DataFrame(rows)
    mappings = build_mappings(frame)
    return encode_interactions(frame, mappings)


@pytest.fixture
def synthetic_items() -> pd.DataFrame:
    return pd.DataFrame(
        [
            {
                "item_id": str(index),
                "title": f"Movie {index}",
                "Action": int(index % 2 == 0),
                "Comedy": int(index % 2 == 1),
            }
            for index in range(1, 7)
        ]
    )


@pytest.fixture
def project_root() -> Path:
    return Path(__file__).resolve().parents[1]
