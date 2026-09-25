from __future__ import annotations

import numpy as np
import pandas as pd


def temporal_train_test_split(
    interactions: pd.DataFrame,
    *,
    test_fraction: float = 1 / 3,
) -> tuple[pd.DataFrame, pd.DataFrame]:
    """Keep each user's earliest interactions for training and latest for test.

    This utility is retained for future experiments that collect user feedback;
    it does not produce an offline recommendation-quality score.
    """

    if not 0 < test_fraction < 1:
        raise ValueError("test_fraction must be between 0 and 1.")
    required = {"user_index", "timestamp"}
    missing = required.difference(interactions.columns)
    if missing:
        raise ValueError(f"Missing temporal split columns: {', '.join(sorted(missing))}")

    ordered = interactions.sort_values(
        ["user_index", "timestamp", "item_index"],
        kind="stable",
    )
    train_parts: list[pd.DataFrame] = []
    test_parts: list[pd.DataFrame] = []
    for _user_index, group in ordered.groupby("user_index", sort=True):
        if len(group) < 2:
            raise ValueError("Each user needs at least two interactions for a temporal split.")
        test_count = max(1, int(np.ceil(len(group) * test_fraction)))
        train_count = len(group) - test_count
        if train_count < 1:
            raise ValueError("Temporal split must leave at least one training interaction.")
        train_parts.append(group.iloc[:train_count])
        test_parts.append(group.iloc[train_count:])

    return (
        pd.concat(train_parts, ignore_index=True),
        pd.concat(test_parts, ignore_index=True),
    )
