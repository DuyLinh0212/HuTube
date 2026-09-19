from __future__ import annotations

import json
import math
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Any

REQUIRED_ARTIFACT_FILES = (
    "model.pt",
    "config.yaml",
    "metrics.json",
    "metadata.json",
    "user_index.json",
    "item_index.json",
    "item_metadata.json",
    "seen_items.npz",
)

BOUNDED_RANKING_PREFIXES = ("precision@", "recall@", "ndcg@", "hitrate@")


@dataclass(frozen=True, slots=True)
class QualityGateResult:
    passed: bool
    checks: dict[str, bool]
    errors: list[str]

    def as_dict(self) -> dict[str, Any]:
        return asdict(self)


def validate_metrics(metrics: dict[str, Any]) -> list[str]:
    errors: list[str] = []
    test_metrics = metrics.get("test")
    if not isinstance(test_metrics, dict):
        return ["metrics.test must be an object."]
    for name, value in test_metrics.items():
        if value is None:
            continue
        if not isinstance(value, (int, float)) or not math.isfinite(float(value)):
            errors.append(f"{name} must be a finite number or null.")
            continue
        if name.startswith(BOUNDED_RANKING_PREFIXES) and not 0.0 <= value <= 1.0:
            errors.append(f"{name} must be in [0, 1].")
        if name.startswith(("catalog_coverage@", "diversity@")) and not 0.0 <= value <= 1.0:
            errors.append(f"{name} must be in [0, 1].")
        if name in {"rmse", "mae"} and value < 0:
            errors.append(f"{name} must be non-negative.")
    return errors


def run_quality_gate(artifact_dir: str | Path) -> QualityGateResult:
    path = Path(artifact_dir).expanduser().resolve()
    missing = [name for name in REQUIRED_ARTIFACT_FILES if not (path / name).is_file()]
    errors = [f"Missing artifact file: {name}" for name in missing]

    metadata_ok = False
    metrics_ok = False
    ranking_artifact_ok = True
    if not missing:
        metadata = json.loads((path / "metadata.json").read_text(encoding="utf-8"))
        metadata_ok = (
            metadata.get("source") == "MOVIELENS"
            and metadata.get("deployable") is False
            and bool(metadata.get("modelVersion"))
        )
        ranking = metadata.get("ranking", {})
        if float(ranking.get("popularityWeight", 0.0)) > 0 and not (
            path / "item_popularity.json"
        ).is_file():
            ranking_artifact_ok = False
            errors.append(
                "item_popularity.json is required when popularityWeight is greater than 0."
            )
        if not metadata_ok:
            errors.append(
                "Benchmark metadata must include source=MOVIELENS, deployable=false, "
                "and modelVersion."
            )
        metrics = json.loads((path / "metrics.json").read_text(encoding="utf-8"))
        metric_errors = validate_metrics(metrics)
        errors.extend(metric_errors)
        metrics_ok = not metric_errors

    checks = {
        "artifact_complete": not missing,
        "benchmark_metadata_safe": metadata_ok,
        "ranking_artifact_consistent": ranking_artifact_ok,
        "metrics_valid": metrics_ok,
    }
    return QualityGateResult(
        passed=not errors and all(checks.values()),
        checks=checks,
        errors=errors,
    )


def write_quality_gate(result: QualityGateResult, path: str | Path) -> Path:
    output = Path(path)
    output.write_text(
        json.dumps(result.as_dict(), ensure_ascii=False, indent=2),
        encoding="utf-8",
    )
    return output
