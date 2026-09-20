from __future__ import annotations

import base64
import csv
import html
import json
from pathlib import Path
from typing import Any

import matplotlib
import numpy as np

matplotlib.use("Agg")
from matplotlib import pyplot as plt  # noqa: E402

DISPLAY_NAMES = {
    "user_based": "User-Based CF",
    "item_based": "Item-Based CF",
    "user_based_cosine": "User-Based · Cosine",
    "user_based_jaccard": "User-Based · Jaccard",
    "user_based_pearson": "User-Based · Pearson",
    "item_based_cosine": "Item-Based · Cosine",
    "item_based_jaccard": "Item-Based · Jaccard",
    "item_based_pearson": "Item-Based · Pearson",
}


def display_name(model_name: str) -> str:
    return DISPLAY_NAMES.get(model_name, model_name.replace("_", " ").title())


def metric_display_name(metric: str) -> str:
    labels = {
        "support_coverage": "Support coverage",
        "catalog_coverage": "Catalog coverage",
        "preference_alignment": "Preference alignment",
        "preference_genre_coverage": "Preference genre coverage",
        "diversity": "Diversity",
        "novelty": "Novelty",
    }
    for prefix, label in labels.items():
        if metric.startswith(f"{prefix}@"):
            return f"{label}@{metric.split('@', 1)[1]}"
    if metric.startswith("collaborative_support@"):
        return f"Collaborative Support@{metric.split('@', 1)[1]}"
    if metric.startswith("collaborative_evidence_strength@"):
        return f"Collaborative Evidence Strength@{metric.split('@', 1)[1]}"
    return metric


def _format(value: Any) -> str:
    return "N/A" if value is None else f"{float(value):.6f}"


def _winner(values: dict[str, float | None]) -> str:
    available = {name: value for name, value in values.items() if value is not None}
    if not available:
        return "N/A"
    winner = max(available, key=available.get)
    return display_name(winner)


def _comparison_rows(model_metrics: dict[str, dict[str, Any]]) -> list[dict[str, Any]]:
    preferred = [
        "collaborative_support@10",
        "collaborative_support@20",
        "collaborative_support@30",
        "collaborative_evidence_strength@10",
        "collaborative_evidence_strength@20",
        "collaborative_evidence_strength@30",
        "catalog_coverage@30",
        "diversity@30",
        "novelty@30",
        "preference_alignment@30",
        "preference_genre_coverage@30",
    ]
    available = {
        metric
        for metrics in model_metrics.values()
        for metric, value in metrics.items()
        if value is not None
    }
    names = [metric for metric in preferred if metric in available]
    names.extend(sorted(available.difference(names)))
    rows: list[dict[str, Any]] = []
    for metric in names:
        values = {model: metrics.get(metric) for model, metrics in model_metrics.items()}
        rows.append({"metric": metric, **values, "winner": _winner(values)})
    return rows


def _save_chart(rows: list[dict[str, Any]], model_names: list[str], path: Path) -> None:
    chart_metrics = {
        "collaborative_support@10",
        "collaborative_support@20",
        "collaborative_support@30",
    }
    chart_rows = [row for row in rows if row["metric"] in chart_metrics]
    if not chart_rows:
        chart_rows = rows[: min(6, len(rows))]
    if not chart_rows:
        return
    x = np.arange(len(chart_rows))
    width = 0.82 / max(1, len(model_names))
    plt.figure(figsize=(14, 6.5))
    for index, model in enumerate(model_names):
        values = [float(row.get(model) or 0.0) for row in chart_rows]
        plt.bar(
            x + (index - (len(model_names) - 1) / 2) * width,
            values,
            width,
            label=display_name(model),
        )
    plt.xticks(x, [row["metric"] for row in chart_rows])
    plt.ylim(0, 1)
    plt.ylabel("Score")
    plt.title("Collaborative Support@K across six pure-CF variants")
    plt.legend(ncol=2, fontsize=8)
    plt.grid(axis="y", alpha=0.25)
    plt.tight_layout()
    plt.savefig(path, dpi=150, bbox_inches="tight")
    plt.close()


def generate_comparison_report(
    *,
    report_dir: Path,
    model_version: str,
    model_metrics: dict[str, dict[str, Any]],
) -> Path:
    report_dir.mkdir(parents=True, exist_ok=True)
    model_names = list(model_metrics)
    rows = _comparison_rows(model_metrics)
    chart = report_dir / "preference_comparison.png"
    _save_chart(rows, model_names, chart)

    payload = {
        "modelVersion": model_version,
        "models": model_metrics,
        "rows": rows,
        "primaryMetric": "collaborative_support@10",
        "evaluation": (
            "intrinsic collaborative evidence; no exact item holdout, recall or "
            "precision target"
        ),
    }
    (report_dir / "cf_comparison.json").write_text(
        json.dumps(payload, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )
    with (report_dir / "cf_comparison.csv").open("w", encoding="utf-8", newline="") as stream:
        fieldnames = ["metric", *model_names, "winner"]
        writer = csv.DictWriter(stream, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)

    table = [
        "| Metric | "
        + " | ".join(display_name(name) for name in model_names)
        + " | Winner |",
        "|---|" + "---:|" * len(model_names) + "---|",
    ]
    table.extend(
        "| {metric} | {values} | {winner} |".format(
            metric=metric_display_name(row["metric"]),
            values=" | ".join(_format(row.get(model)) for model in model_names),
            winner=row["winner"],
        )
        for row in rows
    )
    markdown = [
        f"# Pure CF Comparison — {model_version}",
        "",
        "The primary metric is Collaborative Support@K. It measures whether a "
        "recommended item is supported by similar users or similar observed items. "
        "No exact item holdout, recall or precision target is required.",
        "",
        *table,
        "",
        "![Collaborative Support comparison](./preference_comparison.png)",
        "",
    ]
    (report_dir / "cf_comparison.md").write_text("\n".join(markdown), encoding="utf-8")

    body = "".join(
        "<tr>"
        f"<td>{html.escape(metric_display_name(str(row['metric'])))}</td>"
        + "".join(
            f"<td>{html.escape(_format(row.get(model)))}</td>"
            for model in model_names
        )
        + f"<td>{html.escape(str(row['winner']))}</td></tr>"
        for row in rows
    )
    encoded = base64.b64encode(chart.read_bytes()).decode("ascii") if chart.is_file() else ""
    headers = "".join(
        f"<th>{html.escape(display_name(name))}</th>" for name in model_names
    )
    document = f"""<!doctype html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Pure CF comparison</title>
<style>
body{{font-family:Arial,sans-serif;max-width:1500px;margin:auto;padding:32px;color:#172033}}
table{{border-collapse:collapse;width:100%;margin:24px 0;display:block;overflow-x:auto}}
th,td{{border:1px solid #d7deea;padding:8px;text-align:left;white-space:nowrap}}
th{{background:#edf3fb}}img{{max-width:100%;border:1px solid #d7deea;border-radius:8px}}
</style></head><body>
<h1>Pure CF Comparison — {html.escape(model_version)}</h1>
<p>Primary metrics: Collaborative Support@10, Collaborative Support@20 and
Collaborative Support@30. This is structural collaborative evidence, not a
guarantee of user satisfaction. No exact item holdout, recall or precision target
is used.</p>
<table><thead><tr><th>Metric</th>{headers}<th>Winner</th></tr></thead>
<tbody>{body}</tbody></table>
<img alt="Collaborative Support comparison" src="data:image/png;base64,{encoded}">
</body></html>"""
    output = report_dir / "cf_comparison.html"
    output.write_text(document, encoding="utf-8")
    return output
