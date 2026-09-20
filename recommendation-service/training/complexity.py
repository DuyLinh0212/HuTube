from __future__ import annotations

from platform import platform
from time import perf_counter
from typing import Any

import numpy as np
import pandas as pd

from app.data.mapping import IndexMappings
from app.recommenders.similarity import (
    InteractionMode,
    SimilarityName,
    build_interaction_matrix,
    compute_similarity,
    select_positive_neighbors,
)

STRATEGY_LABELS = {
    "baseline_dense": "Baseline dense",
    "genre_blocked": "Genre-blocked matrices",
}


def strategy_display_name(strategy: str) -> str:
    return STRATEGY_LABELS.get(strategy, strategy.replace("_", " ").title())


def _base_row(
    strategy: str,
    *,
    user_count: int,
    item_count: int,
    similarity: SimilarityName,
    neighbor_count: int,
) -> dict[str, Any]:
    return {
        "strategy": strategy,
        "label": strategy_display_name(strategy),
        "user_count": user_count,
        "item_count": item_count,
        "similarity": similarity,
        "neighbor_count": neighbor_count,
        "matrix_blocks": 0,
        "item_columns_processed": 0,
        "similarity_pair_slots": 0,
        "positive_similarity_pairs": 0,
        "matrix_build_seconds": 0.0,
        "similarity_seconds": 0.0,
        "neighbor_selection_seconds": 0.0,
        "total_seconds": 0.0,
        "dense_interaction_bytes": 0,
        "similarity_matrix_bytes": 0,
        "estimated_peak_bytes": 0,
        "neighbor_slots": 0,
        "neighbor_storage_bytes": 0,
        "notes": "",
    }


def _finish_row(row: dict[str, Any], *, baseline_seconds: float) -> dict[str, Any]:
    row["estimated_peak_megabytes"] = float(row["estimated_peak_bytes"]) / (1024**2)
    row["neighbor_storage_megabytes"] = float(row["neighbor_storage_bytes"]) / (1024**2)
    row["speedup_vs_baseline"] = (
        float(baseline_seconds) / float(row["total_seconds"])
        if float(row["total_seconds"]) > 0
        else None
    )
    return row


def _build_local_matrix(
    observed: pd.DataFrame,
    *,
    user_count: int,
    item_indices: np.ndarray,
    mode: InteractionMode,
) -> np.ndarray:
    matrix = np.zeros((user_count, len(item_indices)), dtype=np.float32)
    if observed.empty or len(item_indices) == 0:
        return matrix

    source_items = observed["item_index"].to_numpy(dtype=np.int64)
    selected = np.isin(source_items, item_indices)
    if not selected.any():
        return matrix

    rows = observed.loc[selected]
    users = rows["user_index"].to_numpy(dtype=np.int64)
    local_items = np.searchsorted(item_indices, rows["item_index"].to_numpy(dtype=np.int64))
    if mode == "binary":
        matrix[users, local_items] = 1.0
        return matrix

    values = rows["rating"].to_numpy(dtype=np.float32)
    totals = np.zeros_like(matrix)
    counts = np.zeros_like(matrix)
    np.add.at(totals, (users, local_items), values)
    np.add.at(counts, (users, local_items), 1.0)
    np.divide(totals, counts, out=matrix, where=counts > 0)
    return matrix


def _genre_item_indices(
    items: pd.DataFrame,
    *,
    genre_names: list[str],
    mappings: IndexMappings,
) -> dict[str, np.ndarray]:
    result: dict[str, np.ndarray] = {}
    for genre in genre_names:
        if genre not in items.columns:
            continue
        selected = items.loc[items[genre].astype(int) > 0, "item_id"].astype(str)
        indices = sorted(
            mappings.item_to_index[item_id]
            for item_id in selected
            if item_id in mappings.item_to_index
        )
        if indices:
            result[genre] = np.asarray(indices, dtype=np.int64)
    return result


def _benchmark_dense(
    interactions: pd.DataFrame,
    *,
    user_count: int,
    item_count: int,
    similarity: SimilarityName,
    interaction_mode: InteractionMode,
    neighbor_count: int,
) -> dict[str, Any]:
    started = perf_counter()
    row = _base_row(
        "baseline_dense",
        user_count=user_count,
        item_count=item_count,
        similarity=similarity,
        neighbor_count=neighbor_count,
    )
    matrix_started = perf_counter()
    matrix = build_interaction_matrix(
        interactions,
        user_count=user_count,
        item_count=item_count,
        mode=interaction_mode,
    )
    row["matrix_build_seconds"] = perf_counter() - matrix_started

    similarity_started = perf_counter()
    similarities = compute_similarity(matrix.T, similarity)
    row["similarity_seconds"] = perf_counter() - similarity_started

    selection_started = perf_counter()
    neighbor_indices, neighbor_similarities = select_positive_neighbors(
        similarities,
        neighbor_count,
    )
    row["neighbor_selection_seconds"] = perf_counter() - selection_started

    similarity_pair_slots = item_count * max(0, item_count - 1) // 2
    row.update(
        {
            "matrix_blocks": 1,
            "item_columns_processed": item_count,
            "similarity_pair_slots": similarity_pair_slots,
            "positive_similarity_pairs": int(
                np.count_nonzero(np.triu(similarities > 0.0, k=1))
            ),
            "dense_interaction_bytes": int(matrix.nbytes),
            "similarity_matrix_bytes": int(similarities.nbytes),
            "neighbor_slots": int(np.count_nonzero(neighbor_indices >= 0)),
            "neighbor_storage_bytes": int(
                neighbor_indices.nbytes + neighbor_similarities.nbytes
            ),
            "notes": (
                "Full user-item matrix and full item-item similarity matrix. "
                "This is the intentionally unoptimized reference."
            ),
        }
    )
    row["estimated_peak_bytes"] = int(
        matrix.nbytes
        + similarities.nbytes
        + neighbor_indices.nbytes
        + neighbor_similarities.nbytes
    )
    row["total_seconds"] = perf_counter() - started
    return row


def _benchmark_genre_blocks(
    interactions: pd.DataFrame,
    *,
    items: pd.DataFrame,
    genre_names: list[str],
    mappings: IndexMappings,
    user_count: int,
    item_count: int,
    similarity: SimilarityName,
    interaction_mode: InteractionMode,
    neighbor_count: int,
) -> dict[str, Any]:
    started = perf_counter()
    row = _base_row(
        "genre_blocked",
        user_count=user_count,
        item_count=item_count,
        similarity=similarity,
        neighbor_count=neighbor_count,
    )
    observed = interactions[interactions["rating"].notna()].copy()
    blocks = _genre_item_indices(items, genre_names=genre_names, mappings=mappings)

    peak_working_bytes = 0
    max_matrix_bytes = 0
    max_similarity_bytes = 0
    total_item_columns = 0
    total_pair_slots = 0
    total_neighbor_slots = 0
    positive_pairs = 0
    matrix_seconds = 0.0
    similarity_seconds = 0.0
    selection_seconds = 0.0
    processed_blocks = 0

    for item_indices in blocks.values():
        if len(item_indices) < 2:
            continue
        processed_blocks += 1
        matrix_started = perf_counter()
        matrix = _build_local_matrix(
            observed,
            user_count=user_count,
            item_indices=item_indices,
            mode=interaction_mode,
        )
        matrix_seconds += perf_counter() - matrix_started

        similarity_started = perf_counter()
        similarities = compute_similarity(matrix.T, similarity)
        similarity_seconds += perf_counter() - similarity_started

        selection_started = perf_counter()
        neighbor_indices, neighbor_similarities = select_positive_neighbors(
            similarities,
            neighbor_count,
        )
        selection_seconds += perf_counter() - selection_started

        block_items = len(item_indices)
        total_item_columns += block_items
        total_pair_slots += block_items * (block_items - 1) // 2
        total_neighbor_slots += int(np.count_nonzero(neighbor_indices >= 0))
        positive_pairs += int(np.count_nonzero(np.triu(similarities > 0.0, k=1)))
        matrix_bytes = int(matrix.nbytes)
        similarity_bytes = int(similarities.nbytes)
        neighbor_bytes = int(neighbor_indices.nbytes + neighbor_similarities.nbytes)
        max_matrix_bytes = max(max_matrix_bytes, matrix_bytes)
        max_similarity_bytes = max(max_similarity_bytes, similarity_bytes)
        peak_working_bytes = max(
            peak_working_bytes,
            matrix_bytes + similarity_bytes + neighbor_bytes,
        )

    row.update(
        {
            "matrix_blocks": processed_blocks,
            "item_columns_processed": total_item_columns,
            "similarity_pair_slots": total_pair_slots,
            "positive_similarity_pairs": positive_pairs,
            "matrix_build_seconds": matrix_seconds,
            "similarity_seconds": similarity_seconds,
            "neighbor_selection_seconds": selection_seconds,
            "dense_interaction_bytes": max_matrix_bytes,
            "similarity_matrix_bytes": max_similarity_bytes,
            "neighbor_slots": total_neighbor_slots,
            "neighbor_storage_bytes": total_neighbor_slots * (8 + 4),
            "estimated_peak_bytes": peak_working_bytes,
            "notes": (
                "One matrix per genre. Multi-genre items may appear in multiple "
                "blocks; cross-genre item pairs are intentionally omitted."
            ),
        }
    )
    row["total_seconds"] = perf_counter() - started
    return row


def benchmark_item_based_strategies(
    interactions: pd.DataFrame,
    *,
    items: pd.DataFrame,
    genre_names: list[str],
    mappings: IndexMappings,
    similarity: SimilarityName = "cosine",
    interaction_mode: InteractionMode = "rating",
    neighbor_count: int = 50,
) -> dict[str, Any]:
    """Benchmark the dense and genre-blocked Item-Based constructions."""
    user_count = len(mappings.user_to_index)
    item_count = len(mappings.item_to_index)
    baseline = _benchmark_dense(
        interactions,
        user_count=user_count,
        item_count=item_count,
        similarity=similarity,
        interaction_mode=interaction_mode,
        neighbor_count=neighbor_count,
    )
    genre = _benchmark_genre_blocks(
        interactions,
        items=items,
        genre_names=genre_names,
        mappings=mappings,
        user_count=user_count,
        item_count=item_count,
        similarity=similarity,
        interaction_mode=interaction_mode,
        neighbor_count=neighbor_count,
    )
    baseline_seconds = float(baseline["total_seconds"])
    for row in (baseline, genre):
        _finish_row(row, baseline_seconds=baseline_seconds)

    return {
        "protocol": {
            "scope": "Item-Based CF construction",
            "similarity": similarity,
            "interaction_mode": interaction_mode,
            "neighbor_count": neighbor_count,
            "measurement": "wall-clock perf_counter on the current machine",
            "baseline": "dense user-item matrix plus full item-item similarity",
            "genre_strategy": (
                "one item similarity block per genre; cross-genre pairs omitted"
            ),
            "genre_metadata_is_used": True,
            "platform": platform(),
        },
        "strategies": [baseline, genre],
    }
