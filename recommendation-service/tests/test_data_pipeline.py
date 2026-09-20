from __future__ import annotations

from datetime import UTC, datetime
from pathlib import Path

import pytest

from app.data.models import InteractionSource, UnifiedInteraction
from app.data.movielens import load_ml100k


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
