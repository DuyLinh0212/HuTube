from __future__ import annotations

import numpy as np
import pandas as pd
import torch


def item_popularity_counts(
    interactions: pd.DataFrame,
    *,
    item_count: int,
) -> np.ndarray:
    counts = np.ones(item_count, dtype=np.float32)
    for item, count in interactions["item_index"].value_counts().items():
        counts[int(item)] += int(count)
    return counts


def normalized_popularity(counts: np.ndarray) -> np.ndarray:
    log_counts = np.log1p(np.asarray(counts, dtype=np.float32))
    spread = float(log_counts.max() - log_counts.min())
    if spread <= 0:
        return np.zeros_like(log_counts)
    return (log_counts - log_counts.min()) / spread


def blend_preference_with_popularity(
    preference_scores: torch.Tensor,
    popularity: np.ndarray | torch.Tensor | None,
    *,
    popularity_weight: float,
) -> torch.Tensor:
    if not 0.0 <= popularity_weight <= 1.0:
        raise ValueError("popularity_weight must be in [0, 1].")
    if popularity_weight == 0.0 or popularity is None:
        return preference_scores
    popularity_tensor = torch.as_tensor(
        popularity,
        dtype=preference_scores.dtype,
        device=preference_scores.device,
    )
    return (
        (1.0 - popularity_weight) * preference_scores
        + popularity_weight * popularity_tensor.unsqueeze(0)
    )
