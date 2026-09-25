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
    if metric == "fit_seconds":
        return "Training time (seconds)"
    if metric == "total_seconds":
        return "Total construction time (seconds)"
    return metric


def _format(value: Any) -> str:
    return "N/A" if value is None else f"{float(value):.6f}"


def _winner(values: dict[str, float | None]) -> str:
    available = {name: value for name, value in values.items() if value is not None}
    if not available:
        return "N/A"
    winner = min(available, key=available.get)
    return display_name(winner)


def _comparison_rows(model_metrics: dict[str, dict[str, Any]]) -> list[dict[str, Any]]:
    """Build a runtime-only comparison table."""

    values = {
        model: data.get("fit_seconds")
        for model, data in model_metrics.items()
    }
    return [
        {
            "metric": "fit_seconds",
            **values,
            "winner": _winner(values),
        }
    ]


def _save_chart(
    model_metrics: dict[str, dict[str, Any]],
    path: Path,
) -> None:
    if not model_metrics:
        return
    names = list(model_metrics)
    values = [float(model_metrics[name].get("fit_seconds") or 0.0) for name in names]
    x = np.arange(len(names))
    figure, axis = plt.subplots(figsize=(12, 5.5))
    axis.bar(x, values, color="#3b6edb")
    axis.set_xticks(x, [display_name(name) for name in names], rotation=20, ha="right")
    axis.set_ylabel("Seconds")
    axis.set_title("Training time by CF variant")
    axis.grid(axis="y", alpha=0.25)
    figure.tight_layout()
    figure.savefig(path, dpi=150, bbox_inches="tight")
    plt.close(figure)


def generate_comparison_report(
    *,
    report_dir: Path,
    model_version: str,
    model_metrics: dict[str, dict[str, Any]],
) -> Path:
    """Write a comparison report containing runtime only."""

    report_dir.mkdir(parents=True, exist_ok=True)
    model_names = list(model_metrics)
    rows = _comparison_rows(model_metrics)
    chart = report_dir / "runtime_comparison.png"
    _save_chart(model_metrics, chart)

    payload = {
        "modelVersion": model_version,
        "comparisonType": "runtime",
        "models": model_metrics,
        "rows": rows,
        "fastestModel": rows[0]["winner"] if rows else "N/A",
    }
    (report_dir / "cf_comparison.json").write_text(
        json.dumps(payload, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )
    with (report_dir / "cf_comparison.csv").open(
        "w", encoding="utf-8", newline=""
    ) as stream:
        fieldnames = ["metric", *model_names, "winner"]
        writer = csv.DictWriter(stream, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)

    table = [
        "| Metric | "
        + " | ".join(display_name(name) for name in model_names)
        + " | Fastest |",
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
        f"# CF Runtime Comparison — {model_version}",
        "",
        "This report compares only the training time of the pure-CF variants.",
        "",
        *table,
        "",
        "![Training time comparison](./runtime_comparison.png)",
        "",
    ]
    (report_dir / "cf_comparison.md").write_text(
        "\n".join(markdown), encoding="utf-8"
    )

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
<title>CF runtime comparison</title>
<style>
body{{font-family:Arial,sans-serif;max-width:1500px;margin:auto;padding:32px;color:#172033}}
table{{border-collapse:collapse;width:100%;margin:24px 0;display:block;overflow-x:auto}}
th,td{{border:1px solid #d7deea;padding:8px;text-align:left;white-space:nowrap}}
th{{background:#edf3fb}}img{{max-width:100%;border:1px solid #d7deea;border-radius:8px}}
</style></head><body>
<h1>CF Runtime Comparison — {html.escape(model_version)}</h1>
<p>The table and chart compare training time in seconds. Lower is faster.</p>
<table><thead><tr><th>Metric</th>{headers}<th>Fastest</th></tr></thead>
<tbody>{body}</tbody></table>
<img alt="Training time comparison" src="data:image/png;base64,{encoded}">
</body></html>"""
    output = report_dir / "cf_comparison.html"
    output.write_text(document, encoding="utf-8")
    return output
