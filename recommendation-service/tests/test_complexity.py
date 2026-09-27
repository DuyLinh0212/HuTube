from __future__ import annotations

from app.data.mapping import build_mappings
from training.complexity import benchmark_item_based


def test_complexity_benchmark_uses_only_dense_item_based_strategy(
    synthetic_interactions,
    synthetic_items,
) -> None:
    mappings = build_mappings(
        synthetic_interactions,
        item_ids=synthetic_items["item_id"].tolist(),
    )
    benchmark = benchmark_item_based(
        synthetic_interactions,
        mappings=mappings,
        similarity="cosine",
        interaction_mode="rating",
        neighbor_count=3,
    )

    rows = benchmark["strategies"]
    assert [row["strategy"] for row in rows] == ["baseline_dense"]
    baseline = rows[0]
    assert baseline["similarity_pair_slots"] == 15
    assert baseline["matrix_blocks"] == 1
    assert baseline["similarity_matrix_bytes"] > 0
    assert float(baseline["total_seconds"]) > 0.0
    assert "genre" not in benchmark["protocol"]
