from __future__ import annotations

from dataclasses import dataclass

import pandas as pd


@dataclass(slots=True)
class TemporalSplit:
    train: pd.DataFrame
    validation: pd.DataFrame
    test: pd.DataFrame


def temporal_split(
    interactions: pd.DataFrame,
    *,
    train_ratio: float = 0.80,
    validation_ratio: float = 0.10,
    test_ratio: float = 0.10,
) -> TemporalSplit:
    total = train_ratio + validation_ratio + test_ratio
    if abs(total - 1.0) > 1e-9:
        raise ValueError("Split ratios must sum to 1.")
    if min(train_ratio, validation_ratio, test_ratio) <= 0:
        raise ValueError("Every split ratio must be positive.")

    train_parts: list[pd.DataFrame] = []
    validation_parts: list[pd.DataFrame] = []
    test_parts: list[pd.DataFrame] = []
    ordered = interactions.sort_values(["user_id", "timestamp", "item_id"], kind="stable")
    for _user_id, group in ordered.groupby("user_id", sort=False):
        count = len(group)
        timestamp_counts = group.groupby("timestamp", sort=True).size()
        if len(timestamp_counts) < 3:
            train_parts.append(group)
            continue
        cumulative = timestamp_counts.cumsum().to_numpy()
        timestamps = timestamp_counts.index
        train_end_index = min(
            range(0, len(timestamps) - 2),
            key=lambda index: abs(cumulative[index] - count * train_ratio),
        )
        validation_end_index = min(
            range(train_end_index + 1, len(timestamps) - 1),
            key=lambda index: abs(
                cumulative[index] - count * (train_ratio + validation_ratio)
            ),
        )
        train_end = timestamps[train_end_index]
        validation_end = timestamps[validation_end_index]
        train_parts.append(group[group["timestamp"] <= train_end])
        validation_parts.append(
            group[
                (group["timestamp"] > train_end)
                & (group["timestamp"] <= validation_end)
            ]
        )
        test_parts.append(group[group["timestamp"] > validation_end])

    def combine(parts: list[pd.DataFrame]) -> pd.DataFrame:
        if not parts:
            return interactions.iloc[0:0].copy()
        return pd.concat(parts, ignore_index=True)

    result = TemporalSplit(
        train=combine(train_parts),
        validation=combine(validation_parts),
        test=combine(test_parts),
    )
    _assert_no_temporal_leakage(result)
    return result


def _assert_no_temporal_leakage(split: TemporalSplit) -> None:
    train_max = split.train.groupby("user_id")["timestamp"].max()
    validation_min = split.validation.groupby("user_id")["timestamp"].min()
    validation_max = split.validation.groupby("user_id")["timestamp"].max()
    test_min = split.test.groupby("user_id")["timestamp"].min()
    for user_id in set(validation_min.index) & set(train_max.index):
        if train_max[user_id] >= validation_min[user_id]:
            raise ValueError(f"Temporal leakage between train and validation for user {user_id}.")
    for user_id in set(test_min.index) & set(validation_max.index):
        if validation_max[user_id] >= test_min[user_id]:
            raise ValueError(f"Temporal leakage between validation and test for user {user_id}.")
