from __future__ import annotations

from datetime import UTC, datetime
from pathlib import Path

import pandas as pd
import pytest

from app.data.models import InteractionSource, UnifiedInteraction
from app.data.movielens import load_ml100k
from app.data.split import temporal_split


def test_null_and_zero_have_different_masks() -> None:
    missing = UnifiedInteraction(
        user_id="1",
        item_id="2",
        source=InteractionSource.MOVIELENS,
        timestamp=datetime.now(UTC),
    )
    observed_zero = UnifiedInteraction(
        user_id="1",
        item_id="2",
        like=False,
        share=False,
        watch_ratio=0.0,
        source=InteractionSource.REAL,
        timestamp=datetime.now(UTC),
    )

    assert missing.masks.like == 0
    assert missing.masks.watch_ratio == 0
    assert observed_zero.masks.like == 1
    assert observed_zero.masks.share == 1
    assert observed_zero.masks.watch_ratio == 1


def test_temporal_split_has_no_future_leakage(synthetic_interactions: pd.DataFrame) -> None:
    split = temporal_split(synthetic_interactions)

    for user_id in synthetic_interactions["user_id"].unique():
        train = split.train[split.train["user_id"] == user_id]
        validation = split.validation[split.validation["user_id"] == user_id]
        test = split.test[split.test["user_id"] == user_id]
        assert train["timestamp"].max() < validation["timestamp"].min()
        assert validation["timestamp"].max() < test["timestamp"].min()


def test_temporal_split_keeps_equal_timestamps_together() -> None:
    started = pd.Timestamp("2024-01-01", tz="UTC")
    frame = pd.DataFrame(
        [
            {
                "user_id": "1",
                "item_id": str(index),
                "timestamp": started + pd.Timedelta(days=index // 2),
            }
            for index in range(8)
        ]
    )

    split = temporal_split(frame, train_ratio=0.5, validation_ratio=0.25, test_ratio=0.25)

    train_times = set(split.train["timestamp"])
    validation_times = set(split.validation["timestamp"])
    test_times = set(split.test["timestamp"])
    assert train_times.isdisjoint(validation_times)
    assert train_times.isdisjoint(test_times)
    assert validation_times.isdisjoint(test_times)


@pytest.mark.dataset
def test_local_movielens_has_official_counts(project_root: Path) -> None:
    data_dir = project_root / "data/raw/movielens/ml-100k"
    if not data_dir.exists():
        pytest.skip("Local MovieLens dataset is intentionally absent from CI.")
    dataset = load_ml100k(data_dir)

    assert dataset.source_summary.as_dict() == {
        "ratings": 100_000,
        "users": 943,
        "items": 1_682,
        "genres": 19,
    }
    behaviors = ["like", "dislike", "comment", "share", "watch_ratio"]
    assert dataset.interactions[behaviors].isna().all().all()
