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
