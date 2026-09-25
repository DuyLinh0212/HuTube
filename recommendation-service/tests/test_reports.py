from __future__ import annotations

from pathlib import Path

from training.comparison import generate_comparison_report
from training.reports import generate_reports


def _runtime_metrics() -> dict[str, object]:
    return {
        "runtime": {
            "models": {
                "user_based": {"fit_seconds": 0.1},
                "item_based": {"fit_seconds": 0.2},
            },
            "total_fit_seconds": 0.3,
        }
    }


def test_html_report_is_self_contained_and_runtime_only(
    tmp_path: Path,
    synthetic_interactions,
) -> None:
    artifact_root = tmp_path / "artifacts"
    (artifact_root / "test-v1").mkdir(parents=True)
    report = generate_reports(
        report_dir=tmp_path / "reports/test-v1",
        artifact_root=artifact_root,
        model_version="test-v1",
        metrics=_runtime_metrics(),
        history=[
            {"model": "user_based", "fit_seconds": 0.1},
            {"model": "item_based", "fit_seconds": 0.2},
        ],
        interactions=synthetic_interactions,
        dataset_summary={"ratings": len(synthetic_interactions), "users": 4, "items": 6},
    )
    content = report.read_text(encoding="utf-8")

    assert "data:image/png;base64," in content
    assert "https://" not in content
    assert "CF Runtime Report" in content
    assert "Support" not in content
    assert (report.parent / "summary.md").is_file()
    assert (report.parent / "cf_comparison.html").is_file()


def test_html_report_includes_complexity_benchmark(
    tmp_path: Path,
    synthetic_interactions,
) -> None:
    artifact_root = tmp_path / "artifacts"
    (artifact_root / "test-v1").mkdir(parents=True)
    metrics = {
        **_runtime_metrics(),
        "complexity_benchmark": {
            "protocol": {"similarity": "cosine"},
            "strategies": [
                {
                    "strategy": "baseline_dense",
                    "label": "Baseline dense",
                    "matrix_blocks": 1,
                    "item_columns_processed": 6,
                    "similarity_pair_slots": 15,
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
    assert "Computational cost" not in content
    assert "Baseline dense" in content
    assert (report.parent / "complexity_benchmark.json").is_file()
    assert (report.parent / "complexity_benchmark.csv").is_file()
    assert (report.parent / "complexity_cost.png").is_file()


def test_cf_comparison_report_is_runtime_only(tmp_path: Path) -> None:
    report = generate_comparison_report(
        report_dir=tmp_path,
        model_version="test-v1",
        model_metrics={
            "user_based": {"fit_seconds": 0.4},
            "item_based": {"fit_seconds": 0.2},
        },
    )
    content = report.read_text(encoding="utf-8")

    assert "data:image/png;base64," in content
    assert "Training time" in content
    assert "Support" not in content
    assert (tmp_path / "cf_comparison.csv").is_file()
    assert (tmp_path / "cf_comparison.json").is_file()


def test_comparison_report_renders_six_variants_and_runtime_labels(tmp_path: Path) -> None:
    metrics = {
        name: {"fit_seconds": 0.1 + index / 100}
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

    assert "Training time (seconds)" in content
    assert "Support" not in content
    assert "Item-Based · Pearson" in content
