from __future__ import annotations

from pathlib import Path

from training.comparison import generate_comparison_report
from training.reports import generate_reports


def _model_metrics(multiplier: float = 1.0) -> dict[str, float]:
    return {
        "preference_alignment@5": 0.6 * multiplier,
        "preference_genre_coverage@5": 0.7 * multiplier,
        "preference_alignment@10": 0.55 * multiplier,
        "preference_genre_coverage@10": 0.8 * multiplier,
        "preference_alignment@20": 0.5 * multiplier,
        "preference_genre_coverage@20": 0.9 * multiplier,
        "catalog_coverage@20": 0.3 * multiplier,
        "diversity@20": 0.7 * multiplier,
        "novelty@20": 8.0 * multiplier,
        "recommendation_count": 20.0,
    }


def test_html_report_is_self_contained(
    tmp_path: Path,
    synthetic_interactions,
) -> None:
    artifact_root = tmp_path / "artifacts"
    artifact_dir = artifact_root / "test-v1"
    artifact_dir.mkdir(parents=True)
    metrics = {
        "models": {
            "user_based": {"preference": _model_metrics()},
            "item_based": {"preference": _model_metrics(0.9)},
        },
        "comparison": {"winner": "user_based"},
        "evaluation_protocol": {"uses_exact_item_holdout": False},
    }
    report = generate_reports(
        report_dir=tmp_path / "reports/test-v1",
        artifact_root=artifact_root,
        model_version="test-v1",
        metrics=metrics,
        history=[
            {"model": "user_based", "fit_seconds": 0.1},
            {"model": "item_based", "fit_seconds": 0.1},
        ],
        interactions=synthetic_interactions,
        dataset_summary={"ratings": len(synthetic_interactions), "users": 4, "items": 6},
    )
    content = report.read_text(encoding="utf-8")

    assert "data:image/png;base64," in content
    assert "https://" not in content
    assert "exact hidden item-ID target" in content
    assert (report.parent / "summary.md").is_file()
    assert (report.parent / "cf_comparison.html").is_file()


def test_html_report_includes_complexity_benchmark(
    tmp_path: Path,
    synthetic_interactions,
) -> None:
    artifact_root = tmp_path / "artifacts"
    (artifact_root / "test-v1").mkdir(parents=True)
    metrics = {
        "models": {"item_based": {"preference": _model_metrics()}},
        "comparison": {"winner": "item_based"},
        "complexity_benchmark": {
            "protocol": {"similarity": "cosine"},
            "strategies": [
                {
                    "strategy": "baseline_dense",
                    "label": "Baseline dense",
                    "matrix_blocks": 1,
                    "item_columns_processed": 6,
                    "similarity_pair_slots": 15,
                    "positive_similarity_pairs": 4,
                    "matrix_build_seconds": 0.1,
                    "candidate_generation_seconds": 0.0,
                    "similarity_seconds": 0.2,
                    "neighbor_selection_seconds": 0.1,
                    "total_seconds": 0.4,
                    "estimated_peak_megabytes": 1.0,
                    "speedup_vs_baseline": 1.0,
                }
            ],
        },
    }
    report = generate_reports(
        report_dir=tmp_path / "reports/test-v1",
        artifact_root=artifact_root,
        model_version="test-v1",
        metrics=metrics,
        history=[{"model": "item_based", "fit_seconds": 0.1}],
        interactions=synthetic_interactions,
        dataset_summary={"ratings": len(synthetic_interactions)},
    )

    content = report.read_text(encoding="utf-8")
    assert "Computational cost benchmark" in content
    assert "Baseline dense" in content
    assert (report.parent / "complexity_benchmark.json").is_file()
    assert (report.parent / "complexity_benchmark.csv").is_file()
    assert (report.parent / "complexity_cost.png").is_file()


def test_cf_comparison_report_is_self_contained(tmp_path: Path) -> None:
    report = generate_comparison_report(
        report_dir=tmp_path,
        model_version="test-v1",
        model_metrics={
            "user_based": _model_metrics(),
            "item_based": _model_metrics(0.9),
        },
    )
    content = report.read_text(encoding="utf-8")

    assert "data:image/png;base64," in content
    assert "https://" not in content
    assert "item holdout" in content
    assert (tmp_path / "cf_comparison.csv").is_file()
    assert (tmp_path / "cf_comparison.json").is_file()


def test_comparison_report_renders_six_variants_and_support_labels(tmp_path: Path) -> None:
    metrics = {
        name: {
            "collaborative_support@10": 0.1 + index / 100,
            "collaborative_support@20": 0.2 + index / 100,
            "collaborative_support@30": 0.3 + index / 100,
        }
        for index, name in enumerate(
            [
                "user_based_cosine",
                "user_based_jaccard",
                "user_based_pearson",
                "item_based_cosine",
                "item_based_jaccard",
                "item_based_pearson",
            ]
        )
    }

    report = generate_comparison_report(
        report_dir=tmp_path,
        model_version="test-v2",
        model_metrics=metrics,
    )
    content = report.read_text(encoding="utf-8")

    assert "Collaborative Support@10" in content
    assert "Collaborative Support@20" in content
    assert "Collaborative Support@30" in content
    assert "Item-Based · Pearson" in content
