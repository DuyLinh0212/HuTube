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

from training.comparison import (
    _comparison_rows,
    display_name,
    generate_comparison_report,
    metric_display_name,
)

BEHAVIORS = ("rating", "like", "dislike", "comment", "share", "watch_ratio")


def _flatten_metrics(payload: dict[str, Any], prefix: str = "") -> list[tuple[str, Any]]:
    rows: list[tuple[str, Any]] = []
    for key, value in payload.items():
        if not prefix and key == "complexity_benchmark":
            continue
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


def _support_chart(metrics: dict[str, dict[str, Any]], report_dir: Path) -> None:
    k_values = sorted(
        {
            int(metric.split("@", 1)[1])
            for values in metrics.values()
            for metric in values
            if metric.startswith("collaborative_support@")
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
            [float(values.get(f"collaborative_support@{k}") or 0.0) for k in k_values],
            width,
            label=display_name(model),
        )
    plt.xticks(x, [str(k) for k in k_values])
    plt.ylim(0, 1)
    plt.xlabel("K")
    plt.ylabel("Collaborative support")
    plt.title("Collaborative Support@K by K")
    plt.legend(ncol=2, fontsize=8)
    plt.grid(axis="y", alpha=0.25)
    _save_figure(report_dir / "collaborative_support_at_k.png")


def _coverage_diversity_chart(
    metrics: dict[str, dict[str, Any]],
    report_dir: Path,
) -> None:
    k_values = sorted(
        {
            int(metric.split("@", 1)[1])
            for values in metrics.values()
            for metric in values
            if metric.startswith("catalog_coverage@")
        }
    )
    if not k_values:
        return
    k = max(k_values)
    names = list(metrics)
    x = np.arange(len(names))
    width = 0.35
    plt.figure(figsize=(9, 5))
    plt.bar(
        x - width / 2,
        [float(metrics[name].get(f"catalog_coverage@{k}") or 0.0) for name in names],
        width,
        label=f"Catalog coverage@{k}",
    )
    plt.bar(
        x + width / 2,
        [float(metrics[name].get(f"diversity@{k}") or 0.0) for name in names],
        width,
        label=f"Diversity@{k}",
    )
    plt.xticks(x, [display_name(name) for name in names], rotation=25, ha="right")
    plt.ylim(0, 1)
    plt.ylabel("Score")
    plt.title("Catalog coverage and diversity")
    plt.legend()
    plt.grid(axis="y", alpha=0.25)
    _save_figure(report_dir / "coverage_diversity.png")


def _complexity_rows(payload: Any) -> list[dict[str, Any]]:
    if not isinstance(payload, dict):
        return []
    strategies = payload.get("strategies")
    if not isinstance(strategies, list):
        return []
    return [row for row in strategies if isinstance(row, dict)]


def _complexity_value(row: dict[str, Any], key: str) -> str:
    value = row.get(key)
    if value is None:
        return "N/A"
    if key in {"total_seconds", "matrix_build_seconds", "candidate_generation_seconds",
               "similarity_seconds", "neighbor_selection_seconds"}:
        return f"{float(value):.6f}"
    if key in {"estimated_peak_megabytes", "neighbor_storage_megabytes"}:
        return f"{float(value):.2f}"
    if key == "speedup_vs_baseline":
        return f"{float(value):.2f}x"
    if isinstance(value, float):
        return f"{value:.6f}"
    if isinstance(value, int):
        return f"{value:,}"
    return str(value)


def _complexity_chart(rows: list[dict[str, Any]], report_dir: Path) -> Path | None:
    if not rows:
        return None
    labels = [str(row.get("label", row.get("strategy", ""))) for row in rows]
    times = [float(row.get("total_seconds") or 0.0) for row in rows]
    memory = [float(row.get("estimated_peak_megabytes") or 0.0) for row in rows]
    x = np.arange(len(labels))
    figure, axes = plt.subplots(1, 2, figsize=(13, 5))
    axes[0].bar(x, times, color="#3b6edb")
    axes[0].set_title("Wall-clock construction time")
    axes[0].set_ylabel("Seconds")
    axes[0].set_xticks(x, labels, rotation=18, ha="right")
    axes[0].grid(axis="y", alpha=0.25)
    axes[1].bar(x, memory, color="#dc7b45")
    axes[1].set_title("Estimated peak working memory")
    axes[1].set_ylabel("MiB")
    axes[1].set_xticks(x, labels, rotation=18, ha="right")
    axes[1].grid(axis="y", alpha=0.25)
    figure.tight_layout()
    output = report_dir / "complexity_cost.png"
    figure.savefig(output, dpi=150, bbox_inches="tight")
    plt.close(figure)
    return output


def _complexity_markdown_table(rows: list[dict[str, Any]]) -> str:
    lines = [
        "| Strategy | Blocks | Items processed | Similarity pair slots | "
        "Positive similarity pairs | Matrix seconds | Similarity seconds | "
        "Neighbor selection seconds | Total seconds | Peak MiB | Speedup | Notes |",
        "|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|",
    ]
    for row in rows:
        lines.append(
            "| {label} | {blocks} | {items} | {slots} | {positive} | "
            "{matrix} | {sim} | {selection} | {total} | {memory} | "
            "{speedup} | {notes} |".format(
                label=row.get("label", row.get("strategy", "")),
                blocks=_complexity_value(row, "matrix_blocks"),
                items=_complexity_value(row, "item_columns_processed"),
                slots=_complexity_value(row, "similarity_pair_slots"),
                positive=_complexity_value(row, "positive_similarity_pairs"),
                matrix=_complexity_value(row, "matrix_build_seconds"),
                sim=_complexity_value(row, "similarity_seconds"),
                selection=_complexity_value(row, "neighbor_selection_seconds"),
                total=_complexity_value(row, "total_seconds"),
                memory=_complexity_value(row, "estimated_peak_megabytes"),
                speedup=_complexity_value(row, "speedup_vs_baseline"),
                notes=str(row.get("notes", "")),
            )
        )
    return "\n".join(lines)


def _complexity_html_table(rows: list[dict[str, Any]]) -> str:
    headers = (
        "<th>Strategy</th><th>Blocks</th><th>Items processed</th>"
        "<th>Similarity pair slots</th><th>Positive similarity pairs</th>"
        "<th>Matrix seconds</th><th>Similarity seconds</th>"
        "<th>Neighbor selection seconds</th><th>Total seconds</th>"
        "<th>Peak MiB</th><th>Speedup</th><th>Notes</th>"
    )
    body = "".join(
        "<tr>"
        f"<td>{html.escape(str(row.get('label', row.get('strategy', ''))))}</td>"
        f"<td>{html.escape(_complexity_value(row, 'matrix_blocks'))}</td>"
        f"<td>{html.escape(_complexity_value(row, 'item_columns_processed'))}</td>"
        f"<td>{html.escape(_complexity_value(row, 'similarity_pair_slots'))}</td>"
        f"<td>{html.escape(_complexity_value(row, 'positive_similarity_pairs'))}</td>"
        f"<td>{html.escape(_complexity_value(row, 'matrix_build_seconds'))}</td>"
        f"<td>{html.escape(_complexity_value(row, 'similarity_seconds'))}</td>"
        f"<td>{html.escape(_complexity_value(row, 'neighbor_selection_seconds'))}</td>"
        f"<td>{html.escape(_complexity_value(row, 'total_seconds'))}</td>"
        f"<td>{html.escape(_complexity_value(row, 'estimated_peak_megabytes'))}</td>"
        f"<td>{html.escape(_complexity_value(row, 'speedup_vs_baseline'))}</td>"
        f"<td>{html.escape(str(row.get('notes', '')))}</td>"
        "</tr>"
        for row in rows
    )
    return (
        "<table class='complexity'><thead><tr>"
        f"{headers}</tr></thead><tbody>{body}</tbody></table>"
    )


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
                float(item.get("collaborative_support@10") or 0.0)
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
    plt.plot(x, alignment, marker="o", label="Best Collaborative Support@10")
    plt.xticks(x, versions, rotation=25, ha="right")
    plt.ylim(0, 1)
    plt.title("Best Collaborative Support@10 by artifact version")
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


def _comparison_html_table(model_metrics: dict[str, dict[str, Any]]) -> str:
    model_names = list(model_metrics)
    rows = _comparison_rows(model_metrics)
    headers = "".join(
        f"<th>{html.escape(display_name(name))}</th>" for name in model_names
    )
    body = "".join(
        "<tr>"
        f"<td>{html.escape(metric_display_name(str(row['metric'])))}</td>"
        + "".join(
            f"<td>{html.escape(_render(row.get(model)))}</td>"
            for model in model_names
        )
        + f"<td>{html.escape(str(row['winner']))}</td></tr>"
        for row in rows
    )
    return (
        "<table class='comparison'><thead><tr><th>Metric</th>"
        + headers
        + "<th>Winner</th></tr></thead><tbody>"
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
    _support_chart(model_metrics, report_dir)
    _coverage_diversity_chart(model_metrics, report_dir)
    coverage = _dataset_charts(interactions, report_dir)
    _version_chart(artifact_root, report_dir)
    complexity_payload = metrics.get("complexity_benchmark")
    complexity_rows = _complexity_rows(complexity_payload)
    _complexity_chart(complexity_rows, report_dir)
    if isinstance(complexity_payload, dict):
        (report_dir / "complexity_benchmark.json").write_text(
            json.dumps(complexity_payload, ensure_ascii=False, indent=2),
            encoding="utf-8",
        )
    if complexity_rows:
        pd.DataFrame(complexity_rows).to_csv(
            report_dir / "complexity_benchmark.csv",
            index=False,
        )
    comparison = generate_comparison_report(
        report_dir=report_dir,
        model_version=model_version,
        model_metrics=model_metrics,
    )

    chart_names = [
        "preference_comparison.png",
        "collaborative_support_at_k.png",
        "coverage_diversity.png",
        "rating_distribution.png",
        "behavior_distribution.png",
        "missing_coverage.png",
        "model_metrics_by_version.png",
        "complexity_cost.png",
    ]
    chart_names = [name for name in chart_names if (report_dir / name).is_file()]
    unavailable = [
        "NDCG@K, recall@K and precision@K: intentionally not used because this benchmark "
        "does not pretend that one hidden item is the only correct recommendation.",
        "Binary behavior metrics: N/A – no observed MovieLens behavior data.",
        "Watch-ratio metrics: N/A – no observed MovieLens behavior data.",
        "Fallback rate: N/A – not a production traffic run.",
        "Cold-start rate: N/A – benchmark contains known users and items.",
    ]
    markdown = [
        f"# Pure Collaborative Filtering Report — {model_version}",
        "",
        "The benchmark compares six pure-CF variants using each user's complete "
        "observed history. Its primary metric is Collaborative Support@10/@20/@30.",
        "",
        "Genre metadata is not used by either CF scorer during training or ranking; "
        "the legacy genre metrics remain secondary diagnostics only.",
        "",
        "## Dataset",
        "",
        _markdown_table(list(dataset_summary.items())),
        "",
        "## Metrics",
        "",
        _markdown_table(flat_metrics),
        "",
        "## Variant comparison",
        "",
        "Collaborative Support@K is the primary comparison metric. It measures "
        "whether recommended items have collaborative evidence from similar users "
        "or similar observed items.",
        "",
        f"Comparison HTML: `{comparison.name}`",
        "",
        "## Behavior coverage",
        "",
        _markdown_table(list(coverage.items())),
        "",
        "## Computational cost benchmark",
        "",
        "The benchmark compares the current dense Item-Based construction and "
        "genre-blocked construction. "
        "The similarity metric is fixed so that the construction strategies "
        "are compared on the same workload.",
        "",
    ]
    if complexity_rows:
        markdown.extend(
            [
                _complexity_markdown_table(complexity_rows),
                "",
                "Similarity pair slots is the number of item pairs available to "
                "the selected similarity calculation. Genre-blocked construction "
                "reports the sum of within-genre slots and intentionally omits "
                "cross-genre pairs. Peak memory is an estimate from numeric arrays, "
                "not a process RSS measurement.",
                "",
            ]
        )
    else:
        markdown.extend(["No complexity benchmark was enabled.", ""])
    markdown.extend(
        [
        "## Not applicable",
        "",
        *[f"- {entry}" for entry in unavailable],
        "",
        "## Charts",
        "",
        *[f"![{name}](./{name})" for name in chart_names],
        "",
        ]
    )
    (report_dir / "summary.md").write_text("\n".join(markdown), encoding="utf-8")

    images = "".join(
        f"<section><h2>{html.escape(name)}</h2>"
        f"<img alt='{html.escape(name)}' src='{_embed_image(report_dir / name)}'></section>"
        for name in chart_names
    )
    unavailable_html = "".join(f"<li>{html.escape(entry)}</li>" for entry in unavailable)
    complexity_html = (
        _complexity_html_table(complexity_rows)
        if complexity_rows
        else "<p>No complexity benchmark was enabled.</p>"
    )
    html_document = f"""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Collaborative Support Report</title>
<style>
body{{font-family:Arial,sans-serif;max-width:1150px;margin:0 auto;padding:32px;color:#172033}}
h1,h2{{color:#173f73}}table{{border-collapse:collapse;width:100%;margin:16px 0 28px}}
th,td{{border:1px solid #d7deea;padding:8px;text-align:left}}th{{background:#edf3fb}}
table.complexity{{display:block;overflow-x:auto}}
img{{max-width:100%;border:1px solid #d7deea;border-radius:8px}}section{{margin:36px 0}}
</style>
</head>
<body>
<h1>Collaborative Support Report — {html.escape(model_version)}</h1>
<p>Six pure-CF variants are evaluated using each user's complete observed history.
The primary metrics are Collaborative Support@10, Collaborative Support@20 and
Collaborative Support@30.</p>
<p>No exact hidden item-ID target is required. Genre metadata is diagnostic-only.</p>
<h2>Dataset</h2>{_html_table(list(dataset_summary.items()))}
<h2>Variant comparison</h2>
<p>Support means that a recommendation is backed by similar users (User-Based)
or similar observed items (Item-Based). It is structural evidence, not a guarantee
of user satisfaction.</p>
{_comparison_html_table(model_metrics)}
<h2>Metrics</h2>{_html_table(flat_metrics)}
<h2>Behavior coverage</h2>{_html_table(list(coverage.items()))}
<h2>Computational cost benchmark</h2>
<p>The benchmark compares dense construction and genre-blocked construction for
the same Item-Based similarity metric. It measures wall-clock time on the current
machine and reports estimated numeric working memory.</p>
{complexity_html}
<h2>Not applicable</h2><ul>{unavailable_html}</ul>
{images}
</body>
</html>
"""
    output = report_dir / "report.html"
    output.write_text(html_document, encoding="utf-8")
    return output
