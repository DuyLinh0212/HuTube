from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
from typing import ClassVar

import numpy as np
import pandas as pd

from .similarity import (
    InteractionMode,
    SimilarityName,
    build_interaction_matrix,
    compute_similarity,
    item_means,
    rank_scores,
    select_positive_neighbors,
)


@dataclass(slots=True)
class UserBasedCF:
    """User-Based Collaborative Filtering implemented with NumPy formulas."""

    model_type: ClassVar[str] = "user_based"
    user_count: int
    item_count: int
    neighbor_count: int
    interaction_mode: InteractionMode
    similarity_name: SimilarityName
    interactions: np.ndarray
    similarities: np.ndarray
    neighbor_indices: np.ndarray
    neighbor_similarities: np.ndarray
    item_means: np.ndarray

    @classmethod
    def fit(
        cls,
        interactions: pd.DataFrame,
        *,
        user_count: int,
        item_count: int,
        neighbor_count: int = 50,
        interaction_mode: InteractionMode = "rating",
        similarity: SimilarityName = "cosine",
    ) -> UserBasedCF:
        matrix = build_interaction_matrix(
            interactions,
            user_count=user_count,
            item_count=item_count,
            mode=interaction_mode,
        )
        if not np.any(matrix > 0):
            raise ValueError("User-Based CF requires at least one observed interaction.")
        similarities = compute_similarity(matrix, similarity)
        neighbor_indices, neighbor_similarities = select_positive_neighbors(
            similarities,
            neighbor_count,
        )
        return cls(
            user_count=user_count,
            item_count=item_count,
            neighbor_count=neighbor_indices.shape[1],
            interaction_mode=interaction_mode,
            similarity_name=similarity,
            interactions=matrix,
            similarities=similarities,
            neighbor_indices=neighbor_indices,
            neighbor_similarities=neighbor_similarities,
            item_means=item_means(matrix),
        )

    def seen_items(self, user_index: int) -> np.ndarray:
        self._validate_user(user_index)
        return np.flatnonzero(self.interactions[user_index] > 0).astype(np.int64)

    def score_all_items(self, user_index: int) -> np.ndarray:
        self._validate_user(user_index)
        neighbors = self.neighbor_indices[user_index]
        if not len(neighbors):
            return self.item_means.copy()
        valid = neighbors >= 0
        neighbors = neighbors[valid]
        weights = self.neighbor_similarities[user_index][valid]
        neighbor_values = self.interactions[neighbors]
        observed = neighbor_values > 0
        weighted = neighbor_values * weights[:, None] * observed
        numerator = weighted.sum(axis=0)
        denominator = (weights[:, None] * observed).sum(axis=0)
        scores = self.item_means.copy()
        np.divide(numerator, denominator, out=scores, where=denominator > 0)
        return scores.astype(np.float32, copy=False)

    def predict_pairs(
        self,
        user_indices: np.ndarray,
        item_indices: np.ndarray,
    ) -> np.ndarray:
        users = np.asarray(user_indices, dtype=np.int64)
        items = np.asarray(item_indices, dtype=np.int64)
        if users.shape != items.shape:
            raise ValueError("user_indices and item_indices must have the same shape.")
        predictions = np.empty(users.shape, dtype=np.float32)
        for user in np.unique(users):
            self._validate_user(int(user))
            positions = np.flatnonzero(users == user)
            predictions[positions] = self.score_all_items(int(user))[items[positions]]
        return predictions

    def recommend(
        self,
        user_index: int,
        *,
        limit: int,
        exclude_item_indices: set[int] | None = None,
    ) -> list[tuple[int, float]]:
        excluded = set(int(value) for value in self.seen_items(user_index))
        excluded.update(exclude_item_indices or set())
        return rank_scores(
            self.score_all_items(user_index),
            limit=limit,
            excluded=excluded,
        )

    def save_npz(self, path: str | Path) -> Path:
        output = Path(path)
        output.parent.mkdir(parents=True, exist_ok=True)
        np.savez_compressed(
            output,
            interactions=self.interactions,
            similarities=self.similarities,
            neighbor_indices=self.neighbor_indices,
            neighbor_similarities=self.neighbor_similarities,
            item_means=self.item_means,
            neighbor_count=np.asarray(self.neighbor_count),
            interaction_mode=np.asarray(self.interaction_mode),
            similarity_name=np.asarray(self.similarity_name),
        )
        return output

    @classmethod
    def load_npz(cls, path: str | Path) -> UserBasedCF:
        with np.load(path, allow_pickle=False) as payload:
            interactions = np.asarray(payload["interactions"], dtype=np.float32)
            return cls(
                user_count=interactions.shape[0],
                item_count=interactions.shape[1],
                neighbor_count=int(payload["neighbor_count"]),
                interaction_mode=str(payload["interaction_mode"].item()),
                similarity_name=str(payload["similarity_name"].item()),
                interactions=interactions,
                similarities=np.asarray(payload["similarities"], dtype=np.float32),
                neighbor_indices=np.asarray(payload["neighbor_indices"], dtype=np.int64),
                neighbor_similarities=np.asarray(
                    payload["neighbor_similarities"],
                    dtype=np.float32,
                ),
                item_means=np.asarray(payload["item_means"], dtype=np.float32),
            )

    def _validate_user(self, user_index: int) -> None:
        if not 0 <= int(user_index) < self.user_count:
            raise IndexError(f"Unknown user index: {user_index}")
