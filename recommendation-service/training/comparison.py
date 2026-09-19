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

LOWER_IS_BETTER = {"rmse", "mae"}


def _winner(metric: str, mbmf: float | None, item_cf: float | None) -> str:
    if mbmf is None or item_cf is None:
        return "N/A"
    if np.isclose(mbmf, item_cf, rtol=1e-6, atol=1e-8):
        return "Tie"
    if metric in LOWER_IS_BETTER:
        return "MBMF" if mbmf < item_cf else "Item-Based CF"
    return "MBMF" if mbmf > item_cf else "Item-Based CF"


def _comparison_rows(
    mbmf_metrics: dict[str, float | None],
    item_cf_metrics: dict[str, float | None],
) -> list[dict[str, Any]]:
    ordered = [
        "rmse",
        "mae",
        *sorted(
            (name for name in mbmf_metrics if "@" in name),
            key=lambda name: (name.split("@", 1)[0], int(name.split("@", 1)[1])),
        ),
    ]
    seen: set[str] = set()
    rows: list[dict[str, Any]] = []
    for metric in ordered:
        if metric in seen or metric not in item_cf_metrics:
            continue
        seen.add(metric)
        mbmf = mbmf_metrics.get(metric)
        item_cf = item_cf_metrics.get(metric)
        rows.append(
            {
                "metric": metric,
                "mbmf": mbmf,
                "item_cf": item_cf,
                "winner": _winner(metric, mbmf, item_cf),
            }
        )
    return rows


def _comparison_chart(
    rows: list[dict[str, Any]],
    output: Path,
) -> None:
    groups = [
        ("Rating error (lower is better)", ["rmse", "mae"]),
        (
            "Top-K ranking (higher is better)",
            [
                row["metric"]
                for row in rows
                if row["metric"].startswith(
                    ("precision@", "recall@", "ndcg@", "hitrate@")
                )
            ],
        ),
        (
            "Catalog properties (higher is better)",
            [
                row["metric"]
                for row in rows
                if row["metric"].startswith(("catalog_coverage@", "diversity@"))
            ],
        ),
        (
            "Novelty (higher means less popular)",
            [row["metric"] for row in rows if row["metric"].startswith("novelty@")],
        ),
    ]
    by_metric = {row["metric"]: row for row in rows}
    figure, axes = plt.subplots(2, 2, figsize=(15, 10))
    for axis, (title, metrics) in zip(axes.flat, groups, strict=True):
        x = np.arange(len(metrics))
        width = 0.38
        axis.bar(
            x - width / 2,
            [by_metric[name]["mbmf"] for name in metrics],
            width,
            label="MBMF",
        )
        axis.bar(
            x + width / 2,
            [by_metric[name]["item_cf"] for name in metrics],
            width,
            label="Item-Based CF",
        )
        axis.set_xticks(x, metrics, rotation=35, ha="right")
        axis.set_title(title)
        axis.grid(axis="y", alpha=0.25)
        axis.legend()
    figure.tight_layout()
    figure.savefig(output, dpi=150, bbox_inches="tight")
    plt.close(figure)


def _format(value: Any) -> str:
    if value is None:
        return "N/A"
    return f"{value:.6f}" if isinstance(value, float) else str(value)


def generate_comparison_report(
    *,
    report_dir: Path,
    model_version: str,
    mbmf_metrics: dict[str, float | None],
    item_cf_metrics: dict[str, float | None],
    neighbor_count: int,
) -> Path:
    report_dir.mkdir(parents=True, exist_ok=True)
    rows = _comparison_rows(mbmf_metrics, item_cf_metrics)
    payload = {
        "modelVersion": model_version,
        "split": "same temporal train+validation/test split",
        "itemCfNeighbors": neighbor_count,
        "mbmf": mbmf_metrics,
        "itemCf": item_cf_metrics,
        "comparison": rows,
    }
    (report_dir / "item_cf_comparison.json").write_text(
        json.dumps(payload, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )
    with (report_dir / "item_cf_comparison.csv").open(
        "w",
        encoding="utf-8",
        newline="",
    ) as stream:
        writer = csv.DictWriter(
            stream,
            fieldnames=["metric", "mbmf", "item_cf", "winner"],
        )
        writer.writeheader()
        writer.writerows(rows)

    chart = report_dir / "item_cf_comparison.png"
    _comparison_chart(rows, chart)
    table_lines = [
        "| Metric | MBMF | Item-Based CF | Better |",
        "|---|---:|---:|---|",
        *[
            "| {metric} | {mbmf} | {item_cf} | {winner} |".format(
                metric=row["metric"],
                mbmf=_format(row["mbmf"]),
                item_cf=_format(row["item_cf"]),
                winner=row["winner"],
            )
            for row in rows
        ],
    ]
    markdown = [
        f"# MBMF vs Item-Based CF — {model_version}",
        "",
        "Both models use the same per-user temporal split. Item-Based CF is fit on "
        f"train+validation with {neighbor_count} neighbors per item.",
        "",
        *table_lines,
        "",
        "![MBMF versus Item-Based CF](./item_cf_comparison.png)",
        "",
    ]
    (report_dir / "item_cf_comparison.md").write_text(
        "\n".join(markdown),
        encoding="utf-8",
    )

    body = "".join(
        "<tr>"
        f"<td>{html.escape(row['metric'])}</td>"
        f"<td>{html.escape(_format(row['mbmf']))}</td>"
        f"<td>{html.escape(_format(row['item_cf']))}</td>"
        f"<td>{html.escape(row['winner'])}</td>"
        "</tr>"
        for row in rows
    )
    encoded = base64.b64encode(chart.read_bytes()).decode("ascii")
    document = f"""<!doctype html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>MBMF vs Item-Based CF</title>
<style>
body{{font-family:Arial,sans-serif;max-width:1200px;margin:auto;padding:32px;color:#172033}}
table{{border-collapse:collapse;width:100%;margin:24px 0}}
th,td{{border:1px solid #d7deea;padding:8px;text-align:left}}th{{background:#edf3fb}}
img{{max-width:100%;border:1px solid #d7deea;border-radius:8px}}
</style></head><body>
<h1>MBMF vs Item-Based CF — {html.escape(model_version)}</h1>
<p>Same temporal split; Item-Based CF uses {neighbor_count} neighbors per item.</p>
<table><thead><tr><th>Metric</th><th>MBMF</th><th>Item-Based CF</th><th>Better</th>
</tr></thead><tbody>{body}</tbody></table>
<img alt="MBMF versus Item-Based CF" src="data:image/png;base64,{encoded}">
</body></html>
"""
    output = report_dir / "item_cf_comparison.html"
    output.write_text(document, encoding="utf-8")
    return output
