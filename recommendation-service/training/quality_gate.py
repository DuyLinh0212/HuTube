from __future__ import annotations

import json
import math
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Any

MODEL_VARIANTS = (
    "user_based_cosine.npz",
    "user_based_jaccard.npz",
    "user_based_pearson.npz",
    "item_based_cosine.npz",
    "item_based_jaccard.npz",
    "item_based_pearson.npz",
)
REQUIRED_ARTIFACT_FILES = (
    *MODEL_VARIANTS,
    "config.yaml",
    "metrics.json",
    "metadata.json",
    "user_index.json",
    "item_index.json",
    "item_metadata.json",
    "seen_items.npz",
)
BOUNDED_PREFIXES = (
    "collaborative_support@",
    "collaborative_evidence_strength@",
    "support_coverage@",
    "preference_alignment@",
    "preference_genre_coverage@",
    "catalog_coverage@",
    "diversity@",
)


@dataclass(frozen=True, slots=True)
class QualityGateResult:
    passed: bool
    checks: dict[str, bool]
    errors: list[str]

    def as_dict(self) -> dict[str, Any]:
        return asdict(self)


def _validate_metric_dict(metrics: dict[str, Any], prefix: str) -> list[str]:
    errors: list[str] = []
    for name, value in metrics.items():
        if value is None:
            continue
        if not isinstance(value, (int, float)) or not math.isfinite(float(value)):
            errors.append(f"{prefix}.{name} must be a finite number or null.")
            continue
        if name.startswith(BOUNDED_PREFIXES) and not 0.0 <= float(value) <= 1.0:
            errors.append(f"{prefix}.{name} must be in [0, 1].")
        if (
            name.startswith("novelty@") or name == "recommendation_count"
        ) and value < 0:
            errors.append(f"{prefix}.{name} must be non-negative.")
    return errors


def validate_metrics(metrics: dict[str, Any]) -> list[str]:
    models = metrics.get("models")
    if not isinstance(models, dict) or not models:
        return ["metrics.models must be a non-empty object."]
    errors: list[str] = []
    for model_name, payload in models.items():
        if not isinstance(payload, dict):
            errors.append(f"metrics.models.{model_name} must be an object.")
            continue
        preference_metrics = payload.get(
            "evaluation",
            payload.get("preference"),
        )
        if not isinstance(preference_metrics, dict):
            errors.append(f"metrics.models.{model_name}.preference must be an object.")
            continue
        errors.extend(
            _validate_metric_dict(
                preference_metrics,
                f"{model_name}.preference",
            )
        )
    return errors


def run_quality_gate(artifact_dir: str | Path) -> QualityGateResult:
    path = Path(artifact_dir).expanduser().resolve()
    missing = [name for name in REQUIRED_ARTIFACT_FILES if not (path / name).is_file()]
    errors = [f"Missing artifact file: {name}" for name in missing]
    metadata_ok = False
    metrics_ok = False
    models_ok = False
    if not missing:
        metadata = json.loads((path / "metadata.json").read_text(encoding="utf-8"))
        model_types = set(metadata.get("modelTypes", []))
        models_ok = (
            {"user_based_cosine", "user_based_jaccard", "user_based_pearson",
             "item_based_cosine", "item_based_jaccard", "item_based_pearson"}
            .issubset(model_types)
            or {"user_based", "item_based"}.issubset(model_types)
        )
        metadata_ok = (
            metadata.get("source") == "MOVIELENS"
            and metadata.get("deployable") is False
            and bool(metadata.get("modelVersion"))
        )
        if not models_ok:
            errors.append(
                "Artifact must contain all six user/item similarity variants, "
                "including both user_based and item_based families."
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
        "models_complete": models_ok,
        "benchmark_metadata_safe": metadata_ok,
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
