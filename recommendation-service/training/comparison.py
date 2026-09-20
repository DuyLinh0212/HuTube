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
}


def _format(value: Any) -> str:
    return "N/A" if value is None else f"{float(value):.6f}"


def _winner(values: dict[str, float | None]) -> str:
    available = {name: value for name, value in values.items() if value is not None}
    if not available:
        return "N/A"
    winner = max(available, key=available.get)
    return DISPLAY_NAMES.get(winner, winner)


def _comparison_rows(model_metrics: dict[str, dict[str, Any]]) -> list[dict[str, Any]]:
    preferred = [
        "preference_alignment@5",
        "preference_genre_coverage@5",
        "preference_alignment@10",
        "preference_genre_coverage@10",
        "preference_alignment@20",
        "preference_genre_coverage@20",
        "catalog_coverage@20",
        "diversity@20",
        "novelty@20",
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
        rows.append(
            {
                "metric": metric,
                **values,
                "winner": _winner(values),
            }
        )
    return rows


def _save_chart(rows: list[dict[str, Any]], model_names: list[str], path: Path) -> None:
    chart_metrics = {
        "preference_alignment@10",
        "preference_genre_coverage@10",
        "catalog_coverage@20",
        "diversity@20",
    }
    chart_rows = [row for row in rows if row["metric"] in chart_metrics]
    if not chart_rows:
        chart_rows = rows[: min(6, len(rows))]
    x = np.arange(len(chart_rows))
    width = 0.8 / max(1, len(model_names))
    plt.figure(figsize=(11, 5.5))
    for index, model in enumerate(model_names):
        values = [float(row.get(model) or 0.0) for row in chart_rows]
        plt.bar(
            x + (index - (len(model_names) - 1) / 2) * width,
            values,
            width,
            label=DISPLAY_NAMES.get(model, model),
        )
    plt.xticks(x, [row["metric"] for row in chart_rows], rotation=25, ha="right")
    plt.ylim(0, 1)
    plt.ylabel("Score")
    plt.title("Preference alignment: User-Based CF versus Item-Based CF")
    plt.legend()
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
        "evaluation": "preference alignment; no exact item holdout",
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
        + " | ".join(DISPLAY_NAMES.get(name, name) for name in model_names)
        + " | Winner |",
        "|---|" + "---:|" * len(model_names) + "---|",
    ]
    table.extend(
        "| {metric} | {values} | {winner} |".format(
            metric=row["metric"],
            values=" | ".join(_format(row.get(model)) for model in model_names),
            winner=row["winner"],
        )
        for row in rows
    )
    markdown = [
        f"# Preference Alignment Comparison — {model_version}",
        "",
        "The models use the complete observed history of each user. "
        "The report measures genre-preference alignment, catalog coverage, diversity "
        "and novelty; it does not require predicting an exact hidden item ID.",
        "",
        *table,
        "",
        "![Preference alignment comparison](./preference_comparison.png)",
        "",
    ]
    (report_dir / "cf_comparison.md").write_text("\n".join(markdown), encoding="utf-8")

    body = "".join(
        "<tr>"
        f"<td>{html.escape(str(row['metric']))}</td>"
        + "".join(
            f"<td>{html.escape(_format(row.get(model)))}</td>"
            for model in model_names
        )
        + f"<td>{html.escape(str(row['winner']))}</td></tr>"
        for row in rows
    )
    encoded = base64.b64encode(chart.read_bytes()).decode("ascii")
    headers = "".join(
        f"<th>{html.escape(DISPLAY_NAMES.get(name, name))}</th>"
        for name in model_names
    )
    document = f"""<!doctype html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Preference alignment comparison</title>
<style>
body{{font-family:Arial,sans-serif;max-width:1200px;margin:auto;padding:32px;color:#172033}}
table{{border-collapse:collapse;width:100%;margin:24px 0}}
th,td{{border:1px solid #d7deea;padding:8px;text-align:left}}th{{background:#edf3fb}}
img{{max-width:100%;border:1px solid #d7deea;border-radius:8px}}
</style></head><body>
<h1>Preference Alignment Comparison — {html.escape(model_version)}</h1>
<p>Complete user history builds an evaluation-only preference profile. No exact
item holdout is required.</p>
<table><thead><tr><th>Metric</th>{headers}<th>Winner</th></tr></thead>
<tbody>{body}</tbody></table>
<img alt="Preference alignment comparison" src="data:image/png;base64,{encoded}">
</body></html>"""
    output = report_dir / "cf_comparison.html"
    output.write_text(document, encoding="utf-8")
    return output
