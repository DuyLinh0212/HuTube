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

from app.data.mapping import IndexMappings
from app.recommenders.base import CollaborativeFilter
from training.comparison import display_name
from training.config import TrainConfig
from training.evaluate import _collaborative_support, recommend_for_users
from training.trainer import fit_all_models

COHORT_THRESHOLDS = (20, 30, 40, 50, 60, 70, 80, 100)


def temporal_train_test_split(
    interactions: pd.DataFrame,
    *,
    test_fraction: float = 1 / 3,
) -> tuple[pd.DataFrame, pd.DataFrame]:
    """Keep each user's earliest 2/3 for training and latest 1/3 for test."""
    if not 0 < test_fraction < 1:
        raise ValueError("test_fraction must be between 0 and 1.")
    required = {"user_index", "timestamp"}
    missing = required.difference(interactions.columns)
    if missing:
        raise ValueError(f"Missing temporal split columns: {', '.join(sorted(missing))}")

    ordered = interactions.sort_values(
        ["user_index", "timestamp", "item_index"],
        kind="stable",
    )
    train_parts: list[pd.DataFrame] = []
    test_parts: list[pd.DataFrame] = []
    for _user_index, group in ordered.groupby("user_index", sort=True):
        if len(group) < 2:
            raise ValueError("Each user needs at least two interactions for a temporal split.")
        test_count = max(1, int(np.ceil(len(group) * test_fraction)))
        train_count = len(group) - test_count
        if train_count < 1:
            raise ValueError("Temporal split must leave at least one training interaction.")
        train_parts.append(group.iloc[:train_count])
        test_parts.append(group.iloc[train_count:])

    train = pd.concat(train_parts, ignore_index=True)
    test = pd.concat(test_parts, ignore_index=True)
    return train, test


def _heldout_overlap(
    recommendations: dict[int, list[tuple[int, float]]],
    test_items: dict[int, set[int]],
    *,
    users: list[int],
    k: int,
) -> float:
    """Diagnostic exact-item overlap; never used as the primary metric."""
    values: list[float] = []
    for user_index in users:
        ranked = recommendations.get(user_index, [])[:k]
        if not ranked:
            continue
        recommended = {item for item, _score in ranked}
        values.append(len(recommended & test_items.get(user_index, set())) / len(ranked))
    return float(np.mean(values)) if values else 0.0


def evaluate_cohorts(
    models: dict[str, CollaborativeFilter],
    *,
    all_interactions: pd.DataFrame,
    train_interactions: pd.DataFrame,
    test_interactions: pd.DataFrame,
    thresholds: tuple[int, ...] = COHORT_THRESHOLDS,
    k_values: tuple[int, ...] = (10, 20, 30),
) -> list[dict[str, Any]]:
    """Evaluate model recommendations by minimum observed-history cohort."""
    if not thresholds:
        raise ValueError("At least one cohort threshold is required.")
    if not k_values or min(k_values) < 1:
        raise ValueError("At least one positive K is required.")

    total_counts = all_interactions.groupby("user_index").size()
    train_counts = train_interactions.groupby("user_index").size()
    test_counts = test_interactions.groupby("user_index").size()
    test_items = {
        int(user_index): {int(item) for item in group["item_index"]}
        for user_index, group in test_interactions.groupby("user_index")
    }
    maximum_k = max(k_values)
    rows: list[dict[str, Any]] = []

    for model_name, model in models.items():
        all_recommendations = recommend_for_users(
            model,
            list(range(model.user_count)),
            top_k=maximum_k,
        )
        family, similarity = model_name.rsplit("_", 1)
        for threshold in thresholds:
            users = [
                int(user_index)
                for user_index, count in total_counts.items()
                if int(count) >= threshold
            ]
            if not users:
                continue
            recommendations = {
                user_index: all_recommendations[user_index] for user_index in users
            }
            row: dict[str, Any] = {
                "minimum_interactions": threshold,
                "user_count": len(users),
                "model": model_name,
                "family": family,
                "similarity": similarity,
                "avg_total_interactions": float(total_counts.loc[users].mean()),
                "avg_train_interactions": float(
                    train_counts.reindex(users).fillna(0).mean()
                ),
                "avg_test_interactions": float(
                    test_counts.reindex(users).fillna(0).mean()
                ),
            }
            for k in k_values:
                support, strength = _collaborative_support(
                    model,
                    recommendations,
                    k=k,
                )
                row[f"collaborative_support@{k}"] = support
                row[f"collaborative_evidence_strength@{k}"] = strength
                row[f"heldout_item_overlap@{k}"] = _heldout_overlap(
                    recommendations,
                    test_items,
                    users=users,
                    k=k,
                )
            rows.append(row)
    return rows


def run_cohort_evaluation(
    interactions: pd.DataFrame,
    *,
    config: TrainConfig,
    mappings: IndexMappings,
) -> tuple[list[dict[str, Any]], dict[str, CollaborativeFilter]]:
    train, test = temporal_train_test_split(interactions)
    fitted = fit_all_models(train, config=config, mappings=mappings)
    models = {model_name: result.model for model_name, result in fitted.items()}
    rows = evaluate_cohorts(
        models,
        all_interactions=interactions,
        train_interactions=train,
        test_interactions=test,
        k_values=tuple(config.evaluation.k),
    )
    return rows, models


def _save_chart(rows: list[dict[str, Any]], path: Path) -> None:
    thresholds = sorted({int(row["minimum_interactions"]) for row in rows})
    models = list(dict.fromkeys(str(row["model"]) for row in rows))
    plt.figure(figsize=(13, 6))
    for model in models:
        values = {
            int(row["minimum_interactions"]): float(row["collaborative_support@10"])
            for row in rows
            if row["model"] == model
        }
        plt.plot(
            thresholds,
            [values.get(threshold, np.nan) for threshold in thresholds],
            marker="o",
            label=display_name(model),
        )
    plt.xticks(thresholds)
    plt.ylim(0, 1)
    plt.xlabel("Minimum total interactions per user")
    plt.ylabel("Collaborative Support@10")
    plt.title("Collaborative Support@10 by user-history cohort")
    plt.grid(alpha=0.25)
    plt.legend(ncol=2, fontsize=8)
    plt.tight_layout()
    plt.savefig(path, dpi=150, bbox_inches="tight")
    plt.close()


def _format(value: Any) -> str:
    if value is None:
        return "N/A"
    if isinstance(value, float):
        return f"{value:.6f}"
    return str(value)


def write_cohort_report(
    *,
    report_dir: Path,
    model_version: str,
    rows: list[dict[str, Any]],
) -> Path:
    report_dir.mkdir(parents=True, exist_ok=True)
    payload = {
        "modelVersion": model_version,
        "protocol": {
            "name": "temporal_cohort",
            "cohort_rule": "users with at least N total interactions",
            "train_fraction": 2 / 3,
            "test_fraction": 1 / 3,
            "split": "earliest interactions train, latest interactions test",
            "primary_metric": "collaborative_support@K",
            "heldout_overlap_role": "diagnostic_only",
        },
        "rows": rows,
    }
    (report_dir / "cohort_metrics.json").write_text(
        json.dumps(payload, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )
    fieldnames = list(rows[0]) if rows else []
    with (report_dir / "cohort_metrics.csv").open("w", encoding="utf-8", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=fieldnames)
        if fieldnames:
            writer.writeheader()
            writer.writerows(rows)

    chart = report_dir / "cohort_support_at_10.png"
    if rows:
        _save_chart(rows, chart)

    thresholds = sorted({int(row["minimum_interactions"]) for row in rows})
    markdown: list[str] = [
        f"# Cohort Top-K Evaluation — {model_version}",
        "",
        "Each user is split temporally: earliest 2/3 for training and latest 1/3 "
        "for test. Cohorts use users with at least N total interactions.",
        "",
        "Collaborative Support@K is the primary metric. Heldout item overlap is "
        "shown only as a diagnostic and is not used to select a winner.",
        "",
    ]
    html_sections: list[str] = []
    for threshold in thresholds:
        cohort_rows = [
            row for row in rows if int(row["minimum_interactions"]) == threshold
        ]
        user_count = int(cohort_rows[0]["user_count"])
        markdown.extend(
            [
                f"## Users with at least {threshold} interactions (n={user_count})",
                "",
                "| Model | Support@10 | Support@20 | Support@30 | "
                "Evidence strength@10 | Holdout overlap@10 (diagnostic) |",
                "|---|---:|---:|---:|---:|---:|",
            ]
        )
        for row in cohort_rows:
            markdown.append(
                "| {model} | {s10} | {s20} | {s30} | {strength} | {overlap} |".format(
                    model=display_name(str(row["model"])),
                    s10=_format(row.get("collaborative_support@10")),
                    s20=_format(row.get("collaborative_support@20")),
                    s30=_format(row.get("collaborative_support@30")),
                    strength=_format(row.get("collaborative_evidence_strength@10")),
                    overlap=_format(row.get("heldout_item_overlap@10")),
                )
            )
        markdown.append("")

        headers = (
            "<th>Model</th><th>Support@10</th><th>Support@20</th>"
            "<th>Support@30</th><th>Evidence strength@10</th>"
            "<th>Holdout overlap@10<br>(diagnostic)</th>"
        )
        body = "".join(
            "<tr>"
            f"<td>{html.escape(display_name(str(row['model'])))}</td>"
            f"<td>{html.escape(_format(row.get('collaborative_support@10')))}</td>"
            f"<td>{html.escape(_format(row.get('collaborative_support@20')))}</td>"
            f"<td>{html.escape(_format(row.get('collaborative_support@30')))}</td>"
            f"<td>{html.escape(_format(row.get('collaborative_evidence_strength@10')))}</td>"
            f"<td>{html.escape(_format(row.get('heldout_item_overlap@10')))}</td>"
            "</tr>"
            for row in cohort_rows
        )
        first = cohort_rows[0]
        html_sections.append(
            f"<h2>Users with at least {threshold} interactions (n={user_count})</h2>"
            f"<p>Average total/train/test interactions: "
            f"{_format(first['avg_total_interactions'])} / "
            f"{_format(first['avg_train_interactions'])} / "
            f"{_format(first['avg_test_interactions'])}</p>"
            f"<table><thead><tr>{headers}</tr></thead><tbody>{body}</tbody></table>"
        )

    chart_html = ""
    if chart.is_file():
        encoded = base64.b64encode(chart.read_bytes()).decode("ascii")
        chart_html = (
            "<h2>Trend</h2><img alt='Collaborative Support@10 by cohort' "
            f"src='data:image/png;base64,{encoded}'>"
        )
    document = f"""<!doctype html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Cohort Top-K Evaluation</title>
<style>
body{{font-family:Arial,sans-serif;max-width:1450px;margin:auto;padding:32px;color:#172033}}
h1,h2{{color:#173f73}}table{{border-collapse:collapse;width:100%;margin:16px 0 32px}}
th,td{{border:1px solid #d7deea;padding:8px;text-align:left;white-space:nowrap}}
th{{background:#edf3fb}}img{{max-width:100%;border:1px solid #d7deea;border-radius:8px}}
</style></head><body>
<h1>Cohort Top-K Evaluation — {html.escape(model_version)}</h1>
<p>Each user uses the earliest 2/3 of interactions for training and the latest
1/3 for test. Cohorts contain users with at least N total interactions.</p>
<p><strong>Primary:</strong> Collaborative Support@10/@20/@30. A recommendation
counts as supported when at least one positive CF path exists. Heldout overlap is
diagnostic-only and is not used as the winner metric.</p>
{''.join(html_sections)}
{chart_html}
</body></html>"""
    output = report_dir / "cohort_report.html"
    output.write_text(document, encoding="utf-8")
    (report_dir / "cohort_summary.md").write_text("\n".join(markdown), encoding="utf-8")
    return output
