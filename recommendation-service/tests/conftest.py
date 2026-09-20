from __future__ import annotations

from datetime import UTC, datetime, timedelta
from pathlib import Path

import pandas as pd
import pytest

from app.data.mapping import build_mappings, encode_interactions


@pytest.fixture
def synthetic_interactions() -> pd.DataFrame:
    started = datetime(2024, 1, 1, tzinfo=UTC)
    watched = {
        "1": {"1": 5.0, "2": 4.0, "3": 3.0},
        "2": {"3": 4.0, "5": 5.0, "6": 4.0},
        "3": {"2": 5.0, "3": 4.0, "4": 5.0},
        "4": {"1": 4.0, "4": 5.0, "6": 3.0},
    }
    rows = []
    for user_id, items in watched.items():
        for offset, (item_id, rating) in enumerate(items.items()):
            rows.append(
                {
                    "user_id": user_id,
                    "item_id": item_id,
                    "rating": rating,
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
