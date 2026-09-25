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

from training.comparison import display_name, generate_comparison_report


def _flatten_metrics(payload: dict[str, Any], prefix: str = "") -> list[tuple[str, Any]]:
    rows: list[tuple[str, Any]] = []
    for key, value in payload.items():
        name = f"{prefix}.{key}" if prefix else key
        if isinstance(value, dict):
            rows.extend(_flatten_metrics(value, name))
        else:
            rows.append((name, value))
    return rows


def _render(value: Any) -> str:
    if value is None:
        return "N/A"
    if isinstance(value, float):
        return f"{value:.6f}"
    return str(value)


def _markdown_table(rows: list[tuple[str, Any]], *, value_header: str = "Value") -> str:
    lines = [f"| Metric | {value_header} |", "|---|---:|"]
    lines.extend(f"| {name} | {_render(value)} |" for name, value in rows)
    return "\n".join(lines)


def _html_table(rows: list[tuple[str, Any]], *, value_header: str = "Value") -> str:
    body = "".join(
        f"<tr><td>{html.escape(name)}</td><td>{html.escape(_render(value))}</td></tr>"
        for name, value in rows
    )
    return (
        "<table><thead><tr><th>Metric</th>"
        f"<th>{html.escape(value_header)}</th></tr></thead><tbody>{body}</tbody></table>"
    )


def _runtime_models(
    history: list[dict[str, Any]],
) -> dict[str, dict[str, float]]:
    return {
        str(row["model"]): {"fit_seconds": float(row["fit_seconds"])}
        for row in history
        if row.get("model") is not None and row.get("fit_seconds") is not None
    }


def _runtime_table(history: list[dict[str, Any]]) -> list[tuple[str, Any]]:
    rows: list[tuple[str, Any]] = []
    for row in history:
        model = str(row.get("model", "unknown"))
        rows.append((f"{display_name(model)} · fit_seconds", row.get("fit_seconds")))
    rows.append(("Total fit time", sum(float(row.get("fit_seconds", 0.0)) for row in history)))
    return rows


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
    if key in {
        "total_seconds",
        "matrix_build_seconds",
        "candidate_generation_seconds",
        "similarity_seconds",
        "neighbor_selection_seconds",
    }:
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
        "| Strategy | Blocks | Items processed | Pair slots | Matrix seconds | "
        "Similarity seconds | Neighbor selection seconds | Total seconds | "
        "Peak MiB | Speedup | Notes |",
        "|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|",
    ]
    for row in rows:
        lines.append(
            "| {label} | {blocks} | {items} | {slots} | {matrix} | {sim} | "
            "{selection} | {total} | {memory} | {speedup} | {notes} |".format(
                label=row.get("label", row.get("strategy", "")),
                blocks=_complexity_value(row, "matrix_blocks"),
                items=_complexity_value(row, "item_columns_processed"),
                slots=_complexity_value(row, "similarity_pair_slots"),
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
        "<th>Pair slots</th><th>Matrix seconds</th><th>Similarity seconds</th>"
        "<th>Neighbor selection seconds</th><th>Total seconds</th>"
        "<th>Peak MiB</th><th>Speedup</th><th>Notes</th>"
    )
    body = "".join(
        "<tr>"
        f"<td>{html.escape(str(row.get('label', row.get('strategy', ''))))}</td>"
        f"<td>{html.escape(_complexity_value(row, 'matrix_blocks'))}</td>"
        f"<td>{html.escape(_complexity_value(row, 'item_columns_processed'))}</td>"
        f"<td>{html.escape(_complexity_value(row, 'similarity_pair_slots'))}</td>"
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
    """Generate a runtime/complexity report without recommendation metrics."""

    del artifact_root, interactions
    report_dir.mkdir(parents=True, exist_ok=True)
    runtime_models = _runtime_models(history)
    runtime_payload = metrics.get("runtime")
    if not isinstance(runtime_payload, dict):
        runtime_payload = {
            "models": runtime_models,
            "total_fit_seconds": sum(
                float(row.get("fit_seconds", 0.0)) for row in history
            ),
        }
    report_metrics: dict[str, Any] = {"runtime": runtime_payload}
    complexity_payload = metrics.get("complexity_benchmark")
    if isinstance(complexity_payload, dict):
        report_metrics["complexity_benchmark"] = complexity_payload

    (report_dir / "metrics.json").write_text(
        json.dumps(report_metrics, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )
    flat_metrics = _flatten_metrics(report_metrics)
    with (report_dir / "metrics.csv").open("w", encoding="utf-8", newline="") as stream:
        writer = csv.writer(stream)
        writer.writerow(["metric", "value"])
        writer.writerows(flat_metrics)
    pd.DataFrame(history).to_csv(report_dir / "training_history.csv", index=False)
    pd.DataFrame([dataset_summary]).to_csv(report_dir / "dataset_summary.csv", index=False)

    comparison = generate_comparison_report(
        report_dir=report_dir,
        model_version=model_version,
        model_metrics=runtime_models,
    )
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

    runtime_rows = _runtime_table(history)
    markdown = [
        f"# CF Runtime Report — {model_version}",
        "",
        "This report contains technical runtime information only.",
        "No offline recommendation-quality score is produced.",
        "",
        "## Dataset context",
        "",
        _markdown_table(list(dataset_summary.items())),
        "",
        "## Model training time",
        "",
        _markdown_table(runtime_rows, value_header="Seconds"),
        "",
        f"Comparison HTML: `{comparison.name}`",
        "",
        "## Similarity construction benchmark",
        "",
        _complexity_markdown_table(complexity_rows)
        if complexity_rows
        else "No complexity benchmark was recorded.",
        "",
        "## Generated files",
        "",
        "- `training_history.csv`: fit time for every CF variant.",
        "- `cf_comparison.csv`: runtime comparison between variants.",
        "- `complexity_benchmark.csv`: construction-time and memory benchmark.",
        "",
    ]
    (report_dir / "summary.md").write_text("\n".join(markdown), encoding="utf-8")

    images = []
    for name in ("runtime_comparison.png", "complexity_cost.png"):
        path = report_dir / name
        if path.is_file():
            images.append(
                f"<section><h2>{html.escape(name)}</h2>"
                f"<img alt='{html.escape(name)}' src='{_embed_image(path)}'></section>"
            )
    complexity_html = (
        _complexity_html_table(complexity_rows)
        if complexity_rows
        else "<p>No complexity benchmark was recorded.</p>"
    )
    document = f"""<!doctype html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>CF Runtime Report</title>
<style>
body{{font-family:Arial,sans-serif;max-width:1500px;margin:auto;padding:32px;color:#172033}}
h1,h2{{color:#173f73}}table{{border-collapse:collapse;width:100%;margin:16px 0 28px}}
th,td{{border:1px solid #d7deea;padding:8px;text-align:left;white-space:nowrap}}
th{{background:#edf3fb}}table.complexity{{display:block;overflow-x:auto}}
img{{max-width:100%;border:1px solid #d7deea;border-radius:8px}}section{{margin:36px 0}}
</style></head><body>
<h1>CF Runtime Report — {html.escape(model_version)}</h1>
<p>This report contains technical runtime information only. It does not claim
that a recommendation is suitable or preferred by a user.</p>
<h2>Dataset context</h2>{_html_table(list(dataset_summary.items()))}
<h2>Model training time</h2>{_html_table(runtime_rows, value_header="Seconds")}
<h2>Similarity construction benchmark</h2>{complexity_html}
{''.join(images)}
</body></html>"""
    output = report_dir / "report.html"
    output.write_text(document, encoding="utf-8")
    return output
