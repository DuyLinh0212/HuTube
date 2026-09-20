from __future__ import annotations

from pathlib import Path
from typing import Protocol

import numpy as np


class CollaborativeFilter(Protocol):
    """Small protocol shared by the two from-scratch CF implementations."""

    model_type: str
    user_count: int
    item_count: int

    def seen_items(self, user_index: int) -> np.ndarray:
        ...

    def score_all_items(self, user_index: int) -> np.ndarray:
        ...

    def predict_pairs(
        self,
        user_indices: np.ndarray,
        item_indices: np.ndarray,
    ) -> np.ndarray:
        ...

    def recommend(
        self,
        user_index: int,
        *,
        limit: int,
        exclude_item_indices: set[int] | None = None,
    ) -> list[tuple[int, float]]:
        ...

    def save_npz(self, path: str | Path) -> Path:
        ...
