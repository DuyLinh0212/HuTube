from __future__ import annotations

from dataclasses import dataclass

import numpy as np
import pandas as pd
from scipy import sparse


@dataclass(slots=True)
class ItemBasedCF:
    """Adjusted-cosine Item-Based CF baseline for explicit MovieLens ratings."""

    user_count: int
    item_count: int
    neighbor_count: int
    ratings: sparse.csr_matrix
    centered_ratings: sparse.csr_matrix
    user_means: np.ndarray
    item_means: np.ndarray
    neighbor_indices: np.ndarray
    neighbor_similarities: np.ndarray

    @classmethod
    def fit(
        cls,
        interactions: pd.DataFrame,
        *,
        user_count: int,
        item_count: int,
        neighbor_count: int = 50,
    ) -> ItemBasedCF:
        if neighbor_count < 1:
            raise ValueError("neighbor_count must be positive.")
        observed = interactions[interactions["rating"].notna()]
        users = observed["user_index"].to_numpy(dtype=np.int64)
        items = observed["item_index"].to_numpy(dtype=np.int64)
        values = observed["rating"].to_numpy(dtype=np.float32)
        if not len(values):
            raise ValueError("Item-Based CF requires at least one observed rating.")

        ratings = sparse.csr_matrix(
            (values, (users, items)),
            shape=(user_count, item_count),
            dtype=np.float32,
        )
        global_mean = float(values.mean())
        user_counts = np.diff(ratings.indptr)
        user_sums = np.asarray(ratings.sum(axis=1)).ravel()
        user_means = np.full(user_count, global_mean, dtype=np.float32)
        np.divide(
            user_sums,
            user_counts,
            out=user_means,
            where=user_counts > 0,
        )

        item_counts = np.bincount(items, minlength=item_count)
        item_sums = np.bincount(items, weights=values, minlength=item_count)
        item_means = np.full(item_count, global_mean, dtype=np.float32)
        np.divide(
            item_sums,
            item_counts,
            out=item_means,
            where=item_counts > 0,
        )

        centered = ratings.copy()
        centered.data = centered.data - np.repeat(user_means, user_counts)
        item_vectors = centered.T.tocsr()
        norms = np.sqrt(np.asarray(item_vectors.multiply(item_vectors).sum(axis=1)).ravel())
        inverse_norms = np.zeros_like(norms, dtype=np.float32)
        np.divide(1.0, norms, out=inverse_norms, where=norms > 0)
        normalized_items = sparse.diags(inverse_norms) @ item_vectors
        similarities = (normalized_items @ normalized_items.T).toarray().astype(np.float32)
        np.fill_diagonal(similarities, 0.0)

        effective_neighbors = min(neighbor_count, max(1, item_count - 1))
        candidate_indices = np.argpartition(
            np.abs(similarities),
            kth=item_count - effective_neighbors,
            axis=1,
        )[:, -effective_neighbors:]
        candidate_values = np.take_along_axis(
            similarities,
            candidate_indices,
            axis=1,
        )
        order = np.argsort(-np.abs(candidate_values), axis=1)
        neighbor_indices = np.take_along_axis(candidate_indices, order, axis=1)
        neighbor_similarities = np.take_along_axis(candidate_values, order, axis=1)

        return cls(
            user_count=user_count,
            item_count=item_count,
            neighbor_count=effective_neighbors,
            ratings=ratings,
            centered_ratings=centered,
            user_means=user_means,
            item_means=item_means,
            neighbor_indices=neighbor_indices,
            neighbor_similarities=neighbor_similarities,
        )

    def seen_items(self, user_index: int) -> np.ndarray:
        start = int(self.ratings.indptr[user_index])
        end = int(self.ratings.indptr[user_index + 1])
        return self.ratings.indices[start:end]

    def score_all_items(self, user_index: int) -> np.ndarray:
        if not 0 <= user_index < self.user_count:
            raise IndexError(f"Unknown user index: {user_index}")
        centered = self.centered_ratings.getrow(user_index).toarray().ravel()
        observed = np.zeros(self.item_count, dtype=np.float32)
        observed[self.seen_items(user_index)] = 1.0
        neighbor_values = centered[self.neighbor_indices]
        neighbor_observed = observed[self.neighbor_indices]
        weighted = self.neighbor_similarities * neighbor_values * neighbor_observed
        denominator = (
            np.abs(self.neighbor_similarities) * neighbor_observed
        ).sum(axis=1)
        numerator = weighted.sum(axis=1)
        scores = self.item_means.copy()
        predicted = denominator > 0
        scores[predicted] = self.user_means[user_index] + (
            numerator[predicted] / denominator[predicted]
        )
        return np.clip(scores, 1.0, 5.0)

    def predict_pairs(
        self,
        user_indices: np.ndarray,
        item_indices: np.ndarray,
    ) -> np.ndarray:
        if user_indices.shape != item_indices.shape:
            raise ValueError("user_indices and item_indices must have the same shape.")
        predictions = np.empty(len(user_indices), dtype=np.float32)
        for user_index in np.unique(user_indices):
            positions = np.flatnonzero(user_indices == user_index)
            scores = self.score_all_items(int(user_index))
            predictions[positions] = scores[item_indices[positions]]
        return predictions

    def recommend(
        self,
        user_index: int,
        *,
        limit: int,
        exclude_item_indices: set[int] | None = None,
    ) -> list[tuple[int, float]]:
        scores = self.score_all_items(user_index)
        excluded = set(int(value) for value in self.seen_items(user_index))
        excluded.update(exclude_item_indices or set())
        if excluded:
            scores[np.asarray(sorted(excluded), dtype=np.int64)] = -np.inf
        count = min(limit, int(np.isfinite(scores).sum()))
        if count <= 0:
            return []
        indices = np.argpartition(scores, -count)[-count:]
        indices = indices[np.argsort(-scores[indices])]
        return [(int(item), float(scores[item])) for item in indices]
