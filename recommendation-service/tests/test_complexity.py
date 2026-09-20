from __future__ import annotations

from app.data.mapping import build_mappings
from training.complexity import benchmark_item_based_strategies


def test_complexity_benchmark_compares_dense_and_genre_blocked_strategies(
    synthetic_interactions,
    synthetic_items,
) -> None:
    mappings = build_mappings(
        synthetic_interactions,
        item_ids=synthetic_items["item_id"].tolist(),
    )
    benchmark = benchmark_item_based_strategies(
        synthetic_interactions,
        items=synthetic_items,
        genre_names=["Action", "Comedy"],
        mappings=mappings,
        similarity="cosine",
        interaction_mode="rating",
        neighbor_count=3,
    )

    rows = benchmark["strategies"]
    assert [row["strategy"] for row in rows] == [
        "baseline_dense",
        "genre_blocked",
    ]
    baseline, genre = rows
    assert baseline["similarity_pair_slots"] == 15
    assert genre["matrix_blocks"] == 2
    assert genre["similarity_pair_slots"] > 0
    assert genre["similarity_matrix_bytes"] < baseline["similarity_matrix_bytes"]
    assert all(float(row["total_seconds"]) > 0.0 for row in rows)
