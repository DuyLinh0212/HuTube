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


def benchmark_item_based(
    interactions: pd.DataFrame,
    *,
    mappings: IndexMappings,
    similarity: SimilarityName = "cosine",
    interaction_mode: InteractionMode = "rating",
    neighbor_count: int = 50,
) -> dict[str, Any]:
    """Benchmark the dense Item-Based construction."""
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
    baseline_seconds = float(baseline["total_seconds"])
    _finish_row(baseline, baseline_seconds=baseline_seconds)

    return {
        "protocol": {
            "scope": "Item-Based CF construction",
            "similarity": similarity,
            "interaction_mode": interaction_mode,
            "neighbor_count": neighbor_count,
            "measurement": "wall-clock perf_counter on the current machine",
            "baseline": "dense user-item matrix plus full item-item similarity",
            "platform": platform(),
        },
        "strategies": [baseline],
    }
