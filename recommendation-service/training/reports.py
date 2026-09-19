from __future__ import annotations

import base64
import csv
import html
import json
from pathlib import Path
from typing import Any

import matplotlib
import numpy as np
import pandas as pd

matplotlib.use("Agg")
from matplotlib import pyplot as plt  # noqa: E402

BEHAVIORS = ("rating", "like", "dislike", "comment", "share", "watch_ratio")


def _flatten_metrics(payload: dict[str, Any], prefix: str = "") -> list[tuple[str, Any]]:
    rows: list[tuple[str, Any]] = []
    for key, value in payload.items():
        name = f"{prefix}.{key}" if prefix else key
        if isinstance(value, dict):
            rows.extend(_flatten_metrics(value, name))
        else:
            rows.append((name, value))
    return rows


def _save_figure(path: Path) -> None:
    plt.tight_layout()
    plt.savefig(path, dpi=150, bbox_inches="tight")
    plt.close()


def _loss_chart(history: list[dict[str, Any]], path: Path) -> None:
    epochs = [int(row["epoch"]) for row in history]
    plt.figure(figsize=(8, 4.5))
    plt.plot(epochs, [float(row["train_loss"]) for row in history], label="Train loss")
    validation = [row.get("validation_loss") for row in history]
    if any(value is not None for value in validation):
        plt.plot(
            epochs,
            [float(value) if value is not None else np.nan for value in validation],
            label="Validation rating loss",
        )
    plt.xlabel("Epoch")
    plt.ylabel("Loss")
    plt.title("Training and validation loss")
    plt.legend()
    plt.grid(alpha=0.25)
    _save_figure(path)


def _ranking_charts(metrics: dict[str, Any], report_dir: Path) -> None:
    test_metrics = metrics["test"]
    k_values = sorted(
        int(key.split("@", 1)[1])
        for key in test_metrics
        if key.startswith("ndcg@")
    )
    plt.figure(figsize=(7, 4.5))
    plt.bar([str(k) for k in k_values], [test_metrics[f"ndcg@{k}"] for k in k_values])
    plt.ylim(0, 1)
    plt.xlabel("K")
    plt.ylabel("NDCG")
    plt.title("NDCG@K on test set")
    plt.grid(axis="y", alpha=0.25)
    _save_figure(report_dir / "ndcg_at_k.png")

    x = np.arange(len(k_values))
    width = 0.36
    plt.figure(figsize=(8, 4.5))
    plt.bar(
        x - width / 2,
        [test_metrics[f"precision@{k}"] for k in k_values],
        width,
        label="Precision",
    )
    plt.bar(
        x + width / 2,
        [test_metrics[f"recall@{k}"] for k in k_values],
        width,
        label="Recall",
    )
    plt.xticks(x, [str(k) for k in k_values])
    plt.ylim(0, 1)
    plt.xlabel("K")
    plt.ylabel("Score")
    plt.title("Precision@K and Recall@K on test set")
    plt.legend()
    plt.grid(axis="y", alpha=0.25)
    _save_figure(report_dir / "precision_recall_at_k.png")


def _dataset_charts(interactions: pd.DataFrame, report_dir: Path) -> dict[str, float]:
    plt.figure(figsize=(7, 4.5))
    rating_counts = interactions["rating"].value_counts().sort_index()
    plt.bar([str(value) for value in rating_counts.index], rating_counts.values)
    plt.xlabel("Rating")
    plt.ylabel("Interactions")
    plt.title("MovieLens rating distribution")
    plt.grid(axis="y", alpha=0.25)
    _save_figure(report_dir / "rating_distribution.png")

    coverage = {
        behavior: float(interactions[behavior].notna().mean()) for behavior in BEHAVIORS
    }
    labels = list(coverage)
    values = [coverage[label] for label in labels]
    plt.figure(figsize=(8, 4.5))
    plt.bar(labels, values)
    plt.ylim(0, 1)
    plt.xticks(rotation=20)
    plt.ylabel("Observed ratio")
    plt.title("Behavior distribution")
    plt.grid(axis="y", alpha=0.25)
    _save_figure(report_dir / "behavior_distribution.png")

    plt.figure(figsize=(8, 4.5))
    plt.bar(labels, [1.0 - value for value in values])
    plt.ylim(0, 1)
    plt.xticks(rotation=20)
    plt.ylabel("Missing ratio")
    plt.title("Missing data coverage")
    plt.grid(axis="y", alpha=0.25)
    _save_figure(report_dir / "missing_coverage.png")
    return coverage


def _version_chart(artifact_root: Path, report_dir: Path) -> None:
    versions: list[str] = []
    ndcg: list[float] = []
    recall: list[float] = []
    rmse: list[float] = []
    for metrics_path in sorted(artifact_root.glob("*/metrics.json")):
        try:
            payload = json.loads(metrics_path.read_text(encoding="utf-8"))
            test = payload["test"]
            versions.append(metrics_path.parent.name)
            ndcg.append(float(test.get("ndcg@10", 0.0)))
            recall.append(float(test.get("recall@10", 0.0)))
            rmse.append(float(test.get("rmse", 0.0)))
        except (KeyError, TypeError, ValueError, json.JSONDecodeError):
            continue
    if not versions:
        return
    x = np.arange(len(versions))
    plt.figure(figsize=(max(8, len(versions) * 1.5), 4.8))
    plt.plot(x, ndcg, marker="o", label="NDCG@10")
    plt.plot(x, recall, marker="o", label="Recall@10")
    plt.plot(x, rmse, marker="o", label="RMSE")
    plt.xticks(x, versions, rotation=25, ha="right")
    plt.title("Model metrics by version")
    plt.legend()
    plt.grid(alpha=0.25)
    _save_figure(report_dir / "model_metrics_by_version.png")


def _markdown_table(rows: list[tuple[str, Any]]) -> str:
    lines = ["| Metric | Value |", "|---|---:|"]
    for name, value in rows:
        rendered = (
            "N/A"
            if value is None
            else f"{value:.6f}"
            if isinstance(value, float)
            else str(value)
        )
        lines.append(f"| {name} | {rendered} |")
    return "\n".join(lines)


def _html_table(rows: list[tuple[str, Any]]) -> str:
    body = []
    for name, value in rows:
        rendered = (
            "N/A"
            if value is None
            else f"{value:.6f}"
            if isinstance(value, float)
            else str(value)
        )
        body.append(
            f"<tr><td>{html.escape(name)}</td><td>{html.escape(rendered)}</td></tr>"
        )
    return (
        "<table><thead><tr><th>Metric</th><th>Value</th></tr></thead><tbody>"
        + "".join(body)
        + "</tbody></table>"
    )


def _embed_image(path: Path) -> str:
    encoded = base64.b64encode(path.read_bytes()).decode("ascii")
    return f"data:image/png;base64,{encoded}"


def generate_reports(
    *,
    report_dir: Path,
    artifact_root: Path,
    model_version: str,
    metrics: dict[str, Any],
    history: list[dict[str, Any]],
    interactions: pd.DataFrame,
    dataset_summary: dict[str, Any],
) -> Path:
    report_dir.mkdir(parents=True, exist_ok=True)
    (report_dir / "metrics.json").write_text(
        json.dumps(metrics, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )
    flat_metrics = _flatten_metrics(metrics)
    with (report_dir / "metrics.csv").open("w", encoding="utf-8", newline="") as stream:
        writer = csv.writer(stream)
        writer.writerow(["metric", "value"])
        writer.writerows(flat_metrics)
    pd.DataFrame(history).to_csv(report_dir / "training_history.csv", index=False)
    pd.DataFrame([dataset_summary]).to_csv(report_dir / "dataset_summary.csv", index=False)

    _loss_chart(history, report_dir / "training_validation_loss.png")
    _ranking_charts(metrics, report_dir)
    coverage = _dataset_charts(interactions, report_dir)
    _version_chart(artifact_root, report_dir)

    chart_names = [
        "training_validation_loss.png",
        "ndcg_at_k.png",
        "precision_recall_at_k.png",
        "rating_distribution.png",
        "behavior_distribution.png",
        "missing_coverage.png",
        "model_metrics_by_version.png",
    ]
    chart_names = [name for name in chart_names if (report_dir / name).is_file()]
    unavailable = [
        "Binary behavior PR/ROC curves: N/A – no observed MovieLens data.",
        "Watch ratio metrics: N/A – no observed MovieLens data.",
        "Fallback rate: N/A – offline benchmark.",
        "Cold-start rate: N/A – offline benchmark.",
    ]
    markdown = [
        f"# MBMF MovieLens 100K Report — {model_version}",
        "",
        "## Dataset",
        "",
        _markdown_table(list(dataset_summary.items())),
        "",
        "## Metrics",
        "",
        _markdown_table(flat_metrics),
        "",
        "## Behavior coverage",
        "",
        _markdown_table(list(coverage.items())),
        "",
        "## Not applicable",
        "",
        *[f"- {entry}" for entry in unavailable],
        "",
        "## Charts",
        "",
        *[f"![{name}](./{name})" for name in chart_names],
        "",
    ]
    (report_dir / "summary.md").write_text("\n".join(markdown), encoding="utf-8")

    images = "".join(
        f"<section><h2>{html.escape(name)}</h2>"
        f"<img alt='{html.escape(name)}' "
        f"src='{_embed_image(report_dir / name)}'></section>"
        for name in chart_names
    )
    unavailable_html = "".join(f"<li>{html.escape(entry)}</li>" for entry in unavailable)
    html_document = f"""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>MBMF MovieLens 100K Report</title>
<style>
body{{font-family:Arial,sans-serif;max-width:1100px;margin:0 auto;padding:32px;color:#172033}}
h1,h2{{color:#173f73}}table{{border-collapse:collapse;width:100%;margin:16px 0 28px}}
th,td{{border:1px solid #d7deea;padding:8px;text-align:left}}th{{background:#edf3fb}}
img{{max-width:100%;border:1px solid #d7deea;border-radius:8px}}section{{margin:36px 0}}
</style>
</head>
<body>
<h1>MBMF MovieLens 100K Report — {html.escape(model_version)}</h1>
<h2>Dataset</h2>{_html_table(list(dataset_summary.items()))}
<h2>Metrics</h2>{_html_table(flat_metrics)}
<h2>Behavior coverage</h2>{_html_table(list(coverage.items()))}
<h2>Not applicable</h2><ul>{unavailable_html}</ul>
{images}
</body>
</html>
"""
    output = report_dir / "report.html"
    output.write_text(html_document, encoding="utf-8")
    return output
