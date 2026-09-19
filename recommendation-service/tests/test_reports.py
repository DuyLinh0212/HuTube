from __future__ import annotations

from pathlib import Path

from training.comparison import generate_comparison_report
from training.reports import generate_reports


def test_html_report_is_self_contained(
    tmp_path: Path,
    synthetic_interactions,
) -> None:
    artifact_root = tmp_path / "artifacts"
    artifact_dir = artifact_root / "test-v1"
    artifact_dir.mkdir(parents=True)
    (artifact_dir / "metrics.json").write_text(
        '{"test":{"ndcg@10":0.2,"recall@10":0.3,"rmse":1.0}}',
        encoding="utf-8",
    )
    metrics = {
        "validation": {"ndcg@5": 0.1, "ndcg@10": 0.2},
        "test": {
            "rmse": 1.0,
            "mae": 0.8,
            "precision@5": 0.1,
            "recall@5": 0.2,
            "ndcg@5": 0.15,
            "hitrate@5": 0.5,
            "precision@10": 0.05,
            "recall@10": 0.3,
            "ndcg@10": 0.2,
            "hitrate@10": 0.6,
        },
    }
    report = generate_reports(
        report_dir=tmp_path / "reports/test-v1",
        artifact_root=artifact_root,
        model_version="test-v1",
        metrics=metrics,
        history=[
            {"epoch": 1, "train_loss": 1.2, "validation_loss": 0.9},
            {"epoch": 2, "train_loss": 0.8, "validation_loss": 0.7},
        ],
        interactions=synthetic_interactions,
        dataset_summary={"ratings": len(synthetic_interactions), "users": 4, "items": 6},
    )
    content = report.read_text(encoding="utf-8")

    assert "data:image/png;base64," in content
    assert "https://" not in content
    assert (report.parent / "summary.md").is_file()


def test_item_cf_comparison_report_is_self_contained(tmp_path: Path) -> None:
    metrics = {
        "rmse": 1.0,
        "mae": 0.8,
        "precision@10": 0.1,
        "recall@10": 0.2,
        "ndcg@10": 0.15,
        "hitrate@10": 0.4,
        "catalog_coverage@10": 0.3,
        "diversity@10": 0.7,
        "novelty@10": 8.0,
    }
    report = generate_comparison_report(
        report_dir=tmp_path,
        model_version="test-v1",
        mbmf_metrics=metrics,
        item_cf_metrics={name: value * 0.9 for name, value in metrics.items()},
        neighbor_count=10,
    )
    content = report.read_text(encoding="utf-8")

    assert "data:image/png;base64," in content
    assert "https://" not in content
    assert (tmp_path / "item_cf_comparison.csv").is_file()
    assert (tmp_path / "item_cf_comparison.json").is_file()
