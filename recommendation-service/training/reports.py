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

from training.comparison import generate_comparison_report

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


def _model_metrics(payload: dict[str, Any]) -> dict[str, dict[str, Any]]:
    if isinstance(payload.get("models"), dict):
        result: dict[str, dict[str, Any]] = {}
        for name, values in payload["models"].items():
            if not isinstance(values, dict):
                continue
            evaluation = values.get("preference", values.get("evaluation", values))
            if isinstance(evaluation, dict):
                result[str(name)] = dict(evaluation)
        return result
    return {"model": dict(payload.get("preference", payload))}


def _preference_chart(metrics: dict[str, dict[str, Any]], report_dir: Path) -> None:
    k_values = sorted(
        {
            int(metric.split("@", 1)[1])
            for values in metrics.values()
            for metric in values
            if metric.startswith("preference_alignment@")
        }
    )
    if not k_values:
        return
    x = np.arange(len(k_values))
    width = 0.8 / max(1, len(metrics))
    plt.figure(figsize=(10, 5))
    for index, (model, values) in enumerate(metrics.items()):
        plt.bar(
            x + (index - (len(metrics) - 1) / 2) * width,
            [float(values.get(f"preference_alignment@{k}") or 0.0) for k in k_values],
            width,
            label=model,
        )
    plt.xticks(x, [str(k) for k in k_values])
    plt.ylim(0, 1)
    plt.xlabel("K")
    plt.ylabel("Preference alignment")
    plt.title("Preference alignment by K")
    plt.legend()
    plt.grid(axis="y", alpha=0.25)
    _save_figure(report_dir / "preference_alignment_at_k.png")


def _coverage_diversity_chart(
    metrics: dict[str, dict[str, Any]],
    report_dir: Path,
) -> None:
    names = list(metrics)
    x = np.arange(len(names))
    width = 0.35
    plt.figure(figsize=(9, 5))
    plt.bar(
        x - width / 2,
        [float(metrics[name].get("catalog_coverage@20") or 0.0) for name in names],
        width,
        label="Catalog coverage@20",
    )
    plt.bar(
        x + width / 2,
        [float(metrics[name].get("diversity@20") or 0.0) for name in names],
        width,
        label="Diversity@20",
    )
    plt.xticks(x, names)
    plt.ylim(0, 1)
    plt.ylabel("Score")
    plt.title("Catalog coverage and diversity")
    plt.legend()
    plt.grid(axis="y", alpha=0.25)
    _save_figure(report_dir / "coverage_diversity.png")


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
    plt.title("Behavior observation coverage")
    plt.grid(axis="y", alpha=0.25)
    _save_figure(report_dir / "behavior_distribution.png")

    plt.figure(figsize=(8, 4.5))
    plt.bar(labels, [1.0 - value for value in values])
    plt.ylim(0, 1)
    plt.xticks(rotation=20)
    plt.ylabel("Missing ratio")
    plt.title("Missing behavior coverage")
    plt.grid(axis="y", alpha=0.25)
    _save_figure(report_dir / "missing_coverage.png")
    return coverage


def _version_chart(artifact_root: Path, report_dir: Path) -> None:
    versions: list[str] = []
    alignment: list[float] = []
    for metrics_path in sorted(artifact_root.glob("*/metrics.json")):
        try:
            payload = json.loads(metrics_path.read_text(encoding="utf-8"))
            models = _model_metrics(payload)
            values = [
                float(item.get("preference_alignment@10") or 0.0)
                for item in models.values()
            ]
            versions.append(metrics_path.parent.name)
            alignment.append(max(values) if values else 0.0)
        except (KeyError, TypeError, ValueError, json.JSONDecodeError):
            continue
    if not versions:
        return
    x = np.arange(len(versions))
    plt.figure(figsize=(max(8, len(versions) * 1.5), 4.8))
    plt.plot(x, alignment, marker="o", label="Best preference alignment@10")
    plt.xticks(x, versions, rotation=25, ha="right")
    plt.ylim(0, 1)
    plt.title("Best preference alignment@10 by artifact version")
    plt.legend()
    plt.grid(alpha=0.25)
    _save_figure(report_dir / "model_metrics_by_version.png")


def _render(value: Any) -> str:
    if value is None:
        return "N/A"
    if isinstance(value, float):
        return f"{value:.6f}"
    return str(value)


def _markdown_table(rows: list[tuple[str, Any]]) -> str:
    lines = ["| Metric | Value |", "|---|---:|"]
    lines.extend(f"| {name} | {_render(value)} |" for name, value in rows)
    return "\n".join(lines)


def _html_table(rows: list[tuple[str, Any]]) -> str:
    body = "".join(
        f"<tr><td>{html.escape(name)}</td><td>{html.escape(_render(value))}</td></tr>"
        for name, value in rows
    )
    return (
        "<table><thead><tr><th>Metric</th><th>Value</th></tr></thead><tbody>"
        + body
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

    model_metrics = _model_metrics(metrics)
    _preference_chart(model_metrics, report_dir)
    _coverage_diversity_chart(model_metrics, report_dir)
    coverage = _dataset_charts(interactions, report_dir)
    _version_chart(artifact_root, report_dir)
    comparison = generate_comparison_report(
        report_dir=report_dir,
        model_version=model_version,
        model_metrics=model_metrics,
    )

    chart_names = [
        "preference_comparison.png",
        "preference_alignment_at_k.png",
        "coverage_diversity.png",
        "rating_distribution.png",
        "behavior_distribution.png",
        "missing_coverage.png",
        "model_metrics_by_version.png",
    ]
    chart_names = [name for name in chart_names if (report_dir / name).is_file()]
    unavailable = [
        "Exact item-ID holdout metrics: intentionally not used.",
        "Binary behavior metrics: N/A – no observed MovieLens behavior data.",
        "Watch-ratio metrics: N/A – no observed MovieLens behavior data.",
        "Fallback rate: N/A – not a production traffic run.",
        "Cold-start rate: N/A – benchmark contains known users and items.",
    ]
    markdown = [
        f"# Pure Collaborative Filtering Report — {model_version}",
        "",
        "The benchmark compares User-Based CF and Item-Based CF using each user's "
        "complete observed history. It evaluates preference alignment rather than "
        "forcing the model to recover one hidden item ID.",
        "",
        "Genre metadata is used only to build the evaluation profile and is not used "
        "by either CF scorer during training or ranking.",
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
        f"Comparison HTML: `{comparison.name}`",
        "",
    ]
    (report_dir / "summary.md").write_text("\n".join(markdown), encoding="utf-8")

    images = "".join(
        f"<section><h2>{html.escape(name)}</h2>"
        f"<img alt='{html.escape(name)}' src='{_embed_image(report_dir / name)}'></section>"
        for name in chart_names
    )
    unavailable_html = "".join(f"<li>{html.escape(entry)}</li>" for entry in unavailable)
    html_document = f"""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Preference Alignment Report</title>
<style>
body{{font-family:Arial,sans-serif;max-width:1150px;margin:0 auto;padding:32px;color:#172033}}
h1,h2{{color:#173f73}}table{{border-collapse:collapse;width:100%;margin:16px 0 28px}}
th,td{{border:1px solid #d7deea;padding:8px;text-align:left}}th{{background:#edf3fb}}
img{{max-width:100%;border:1px solid #d7deea;border-radius:8px}}section{{margin:36px 0}}
</style>
</head>
<body>
<h1>Preference Alignment Report — {html.escape(model_version)}</h1>
<p>User-Based CF and Item-Based CF are evaluated against each user's complete
preference profile.</p>
<p>No exact hidden item-ID target is required. Genre metadata is evaluation-only.</p>
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
