from __future__ import annotations

from dataclasses import dataclass

import numpy as np
import pandas as pd

from .item_cf import ItemBasedCF
from .similarity import InteractionMode, SimilarityName, build_interaction_matrix, item_means


@dataclass(slots=True)
class IncrementalItemBasedCF(ItemBasedCF):
    """Cosine Item-Based CF that maintains pair statistics as ratings arrive.

    The model keeps a dense dot-product matrix so updates can touch only pairs
    involving changed items. The initial build remains a full matrix operation.
    User and item indices must already exist in the model mappings.
    """

    pair_dots: np.ndarray | None = None
    norm2: np.ndarray | None = None

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
    ) -> IncrementalItemBasedCF:
        if similarity != "cosine":
            raise ValueError("IncrementalItemBasedCF currently supports cosine only.")
        matrix = build_interaction_matrix(
            interactions,
            user_count=user_count,
            item_count=item_count,
            mode=interaction_mode,
        )
        observed = np.zeros((user_count, item_count), dtype=bool)
        if not interactions.empty:
            users = interactions["user_index"].to_numpy(dtype=np.int64)
            items = interactions["item_index"].to_numpy(dtype=np.int64)
            observed[users, items] = True
        if not np.any(matrix > 0):
            raise ValueError("Incremental Item-Based CF requires an observed interaction.")

        pair_dots = np.asarray(matrix.T @ matrix, dtype=np.float32)
        norm2 = np.einsum("ui,ui->i", matrix, matrix, dtype=np.float32)
        similarities = cls._similarities_from_stats(pair_dots, norm2)
        neighbor_indices, neighbor_similarities = cls._select_neighbors(
            similarities, neighbor_count
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
            item_means=item_means(matrix, observed),
            observed=observed,
            pair_dots=pair_dots,
            norm2=norm2,
        )

    @staticmethod
    def _similarities_from_stats(pair_dots: np.ndarray, norm2: np.ndarray) -> np.ndarray:
        denominator = np.sqrt(norm2[:, None] * norm2[None, :])
        similarities = np.zeros_like(pair_dots, dtype=np.float32)
        np.divide(pair_dots, denominator, out=similarities, where=denominator > 0)
        np.fill_diagonal(similarities, 0.0)
        return np.clip(similarities, 0.0, 1.0)

    @staticmethod
    def _select_neighbors(
        similarities: np.ndarray, neighbor_count: int
    ) -> tuple[np.ndarray, np.ndarray]:
        if neighbor_count < 1:
            raise ValueError("neighbor_count must be positive.")
        item_count = similarities.shape[0]
        width = min(neighbor_count, max(0, item_count - 1))
        indices = np.full((item_count, width), -1, dtype=np.int64)
        values = np.zeros((item_count, width), dtype=np.float32)
        for item in range(item_count):
            candidates = np.flatnonzero(similarities[item] > 0.0)
            candidates = candidates[candidates != item]
            ordered = sorted(
                (int(candidate) for candidate in candidates),
                key=lambda candidate: (-float(similarities[item, candidate]), candidate),
            )[:width]
            if ordered:
                chosen = np.asarray(ordered, dtype=np.int64)
                indices[item, : len(chosen)] = chosen
                values[item, : len(chosen)] = similarities[item, chosen]
        return indices, values

    def update_batch(self, updates: pd.DataFrame) -> int:
        """Apply (possibly new or revised) user-item ratings; return changed items.

        Each update replaces the user's prior value for that item. Users and
        items must be represented by the existing model's integer mappings.
        """
        required = {"user_index", "item_index", "rating"}
        missing = required.difference(updates.columns)
        if missing:
            raise ValueError(f"Missing update columns: {', '.join(sorted(missing))}")
        touched: set[int] = set()
        for row in updates.itertuples(index=False):
            user = int(row.user_index)
            item = int(row.item_index)
            new_value = float(row.rating)
            if not 0 <= user < self.user_count or not 0 <= item < self.item_count:
                raise ValueError("Update index is outside the model's fixed mappings.")
            if not np.isfinite(new_value) or new_value < 0:
                raise ValueError("Ratings must be finite and non-negative.")
            if self.interaction_mode == "binary":
                new_value = float(new_value > 0.0)

            observed = self.observed
            assert observed is not None and self.pair_dots is not None and self.norm2 is not None
            was_observed = bool(observed[user, item])
            old_value = float(self.interactions[user, item]) if was_observed else 0.0
            delta = new_value - old_value
            if delta == 0.0:
                observed[user, item] = True
                if not was_observed:
                    # A newly observed zero leaves cosine stats unchanged but
                    # changes the item-mean denominator used by the fallback.
                    touched.add(item)
                continue

            other_items = np.flatnonzero(observed[user])
            other_items = other_items[other_items != item]
            self.norm2[item] += np.float32(new_value * new_value - old_value * old_value)
            if other_items.size:
                contribution = delta * self.interactions[user, other_items]
                self.pair_dots[item, other_items] += contribution
                self.pair_dots[other_items, item] += contribution
                touched.update(int(other) for other in other_items)
            self.interactions[user, item] = np.float32(new_value)
            observed[user, item] = True
            touched.add(item)

        if touched:
            affected = np.fromiter(sorted(touched), dtype=np.int64)
            denominator = np.sqrt(self.norm2[affected, None] * self.norm2[None, :])
            updated_rows = np.zeros_like(self.pair_dots[affected])
            np.divide(
                self.pair_dots[affected],
                denominator,
                out=updated_rows,
                where=denominator > 0,
            )
            updated_rows = np.clip(updated_rows, 0.0, 1.0)
            updated_rows[np.arange(len(affected)), affected] = 0.0
            self.similarities[affected, :] = updated_rows
            self.similarities[:, affected] = updated_rows.T

            # Recompute only item means whose interactions changed.
            observed = self.observed
            assert observed is not None
            totals = self.interactions[:, affected].sum(axis=0)
            counts = observed[:, affected].sum(axis=0)
            means = np.zeros(len(affected), dtype=np.float32)
            np.divide(totals, counts, out=means, where=counts > 0)
            self.item_means[affected] = means

            # Similarities can affect either endpoint's directed Top-K list.
            for item in affected:
                candidates = np.flatnonzero(self.similarities[item] > 0.0)
                candidates = candidates[candidates != item]
                candidates = sorted(
                    (int(candidate) for candidate in candidates),
                    key=lambda candidate: (-float(self.similarities[item, candidate]), candidate),
                )[: self.neighbor_count]
                self.neighbor_indices[item].fill(-1)
                self.neighbor_similarities[item].fill(0.0)
                if candidates:
                    selected = np.asarray(candidates, dtype=np.int64)
                    self.neighbor_indices[item, : len(selected)] = selected
                    self.neighbor_similarities[item, : len(selected)] = self.similarities[
                        item, selected
                    ]
        return len(touched)
