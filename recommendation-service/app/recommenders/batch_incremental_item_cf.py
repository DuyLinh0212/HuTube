from __future__ import annotations

import numpy as np
import pandas as pd

from .incremental_item_cf import IncrementalItemBasedCF


class BatchIncrementalItemBasedCF(IncrementalItemBasedCF):
    """Item-Based cosine CF updated by one batched Gram-matrix delta."""

    def update_batch(self, updates: pd.DataFrame) -> int:
        """Apply a batch by replacing affected users' Gram contributions once.

        Returns the number of item rows whose similarities/Top-K may change.
        User/item indices must already exist in the model mappings.
        """
        required = {"user_index", "item_index", "rating"}
        missing = required.difference(updates.columns)
        if missing:
            raise ValueError(f"Missing update columns: {', '.join(sorted(missing))}")
        if updates.empty:
            return 0

        user_ids = np.asarray(updates["user_index"], dtype=np.int64)
        item_ids = np.asarray(updates["item_index"], dtype=np.int64)
        values = np.asarray(updates["rating"], dtype=np.float32)
        if (
            (user_ids < 0).any()
            or (user_ids >= self.user_count).any()
            or (item_ids < 0).any()
            or (item_ids >= self.item_count).any()
        ):
            raise ValueError("Update index is outside the model's fixed mappings.")
        if not np.isfinite(values).all() or (values < 0).any():
            raise ValueError("Ratings must be finite and non-negative.")
        if self.interaction_mode == "binary":
            values = (values > 0).astype(np.float32)

        users, inverse = np.unique(user_ids, return_inverse=True)
        old_rows = self.interactions[users].copy()
        new_rows = old_rows.copy()
        observed = self.observed
        assert observed is not None and self.pair_dots is not None and self.norm2 is not None
        old_observed = observed[users].copy()
        new_observed = old_observed.copy()

        changed_user_rows: set[int] = set()
        dirty_mean_items: set[int] = set()
        for local_user, item, value in zip(
            inverse, item_ids, values, strict=True
        ):
            local = int(local_user)
            item = int(item)
            previous = float(new_rows[local, item]) if new_observed[local, item] else 0.0
            was_observed = bool(new_observed[local, item])
            if float(value) != previous:
                new_rows[local, item] = value
                changed_user_rows.add(local)
                dirty_mean_items.add(item)
            elif not was_observed:
                dirty_mean_items.add(item)
            new_observed[local, item] = True

        if changed_user_rows:
            changed_local = np.asarray(sorted(changed_user_rows), dtype=np.int64)
            old_changed = old_rows[changed_local]
            new_changed = new_rows[changed_local]
            delta_gram = new_changed.T @ new_changed - old_changed.T @ old_changed
            self.pair_dots += delta_gram
            self.norm2[:] = np.diag(self.pair_dots)

            dirty_similarity: set[int] = set()
            for local in changed_local:
                dirty_similarity.update(np.flatnonzero(old_rows[local] != 0.0).tolist())
                dirty_similarity.update(np.flatnonzero(new_rows[local] != 0.0).tolist())
            dirty = np.fromiter(sorted(dirty_similarity), dtype=np.int64)
        else:
            dirty = np.empty(0, dtype=np.int64)

        self.interactions[users] = new_rows
        observed[users] = new_observed

        if dirty_mean_items:
            mean_items = np.fromiter(sorted(dirty_mean_items), dtype=np.int64)
            totals = self.interactions[:, mean_items].sum(axis=0)
            counts = observed[:, mean_items].sum(axis=0)
            means = np.zeros(len(mean_items), dtype=np.float32)
            np.divide(totals, counts, out=means, where=counts > 0)
            self.item_means[mean_items] = means

        if dirty.size:
            denominator = np.sqrt(self.norm2[dirty, None] * self.norm2[None, :])
            updated_rows = np.zeros_like(self.pair_dots[dirty])
            np.divide(
                self.pair_dots[dirty],
                denominator,
                out=updated_rows,
                where=denominator > 0,
            )
            updated_rows = np.clip(updated_rows, 0.0, 1.0)
            updated_rows[np.arange(len(dirty)), dirty] = 0.0
            self.similarities[dirty, :] = updated_rows
            self.similarities[:, dirty] = updated_rows.T
            self._refresh_dirty_rows(dirty)
        return int(dirty.size)

    def _refresh_dirty_rows(self, dirty: np.ndarray) -> None:
        for item in dirty:
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


class BatchIncrementalItemBasedCFPartialTopK(BatchIncrementalItemBasedCF):
    """Batch Gram CF using partial selection instead of sorting every candidate."""

    @staticmethod
    def _top_k(row: np.ndarray, item: int, width: int) -> np.ndarray:
        candidates = np.flatnonzero(row > 0.0)
        candidates = candidates[candidates != item]
        if len(candidates) <= width:
            selected = candidates
        else:
            scores = row[candidates]
            partition = np.argpartition(scores, -width)[-width:]
            cutoff = float(np.min(scores[partition]))
            better = candidates[scores > cutoff]
            tied = candidates[scores == cutoff]
            needed = width - len(better)
            if len(tied) > needed:
                tied = tied[np.argpartition(tied, needed - 1)[:needed]]
            selected = np.concatenate((better, tied))
        if selected.size:
            order = np.lexsort((selected, -row[selected]))
            selected = selected[order]
        return selected[:width]

    @staticmethod
    def _select_neighbors(
        similarity: np.ndarray, neighbor_count: int
    ) -> tuple[np.ndarray, np.ndarray]:
        if neighbor_count < 1:
            raise ValueError("neighbor_count must be positive.")
        item_count = similarity.shape[0]
        width = min(neighbor_count, max(0, item_count - 1))
        indices = np.full((item_count, width), -1, dtype=np.int64)
        values = np.zeros((item_count, width), dtype=np.float32)
        for item in range(item_count):
            selected = BatchIncrementalItemBasedCFPartialTopK._top_k(
                similarity[item], item, width
            )
            indices[item, : len(selected)] = selected
            values[item, : len(selected)] = similarity[item, selected]
        return indices, values

    def _refresh_dirty_rows(self, dirty: np.ndarray) -> None:
        for item in dirty:
            selected = self._top_k(
                self.similarities[item], int(item), self.neighbor_count
            )
            self.neighbor_indices[item].fill(-1)
            self.neighbor_similarities[item].fill(0.0)
            self.neighbor_indices[item, : len(selected)] = selected
            self.neighbor_similarities[item, : len(selected)] = self.similarities[
                item, selected
            ]
