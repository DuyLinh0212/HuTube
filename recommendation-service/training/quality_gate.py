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


@dataclass(frozen=True, slots=True)
class QualityGateResult:
    passed: bool
    checks: dict[str, bool]
    errors: list[str]

    def as_dict(self) -> dict[str, Any]:
        return asdict(self)


def _finite_non_negative(value: Any, label: str) -> list[str]:
    if not isinstance(value, (int, float)) or not math.isfinite(float(value)):
        return [f"{label} must be a finite number."]
    if float(value) < 0:
        return [f"{label} must be non-negative."]
    return []


def validate_metrics(metrics: dict[str, Any]) -> list[str]:
    """Validate the runtime-only metrics payload."""

    runtime = metrics.get("runtime")
    if not isinstance(runtime, dict):
        return ["metrics.runtime must be an object."]

    models = runtime.get("models")
    if not isinstance(models, dict) or not models:
        return ["metrics.runtime.models must be a non-empty object."]

    errors: list[str] = []
    for model_name, payload in models.items():
        if not isinstance(payload, dict):
            errors.append(f"runtime.models.{model_name} must be an object.")
            continue
        errors.extend(
            _finite_non_negative(
                payload.get("fit_seconds"),
                f"runtime.models.{model_name}.fit_seconds",
            )
        )
    if "total_fit_seconds" in runtime:
        errors.extend(
            _finite_non_negative(
                runtime["total_fit_seconds"],
                "runtime.total_fit_seconds",
            )
        )

    complexity = metrics.get("complexity_benchmark")
    if isinstance(complexity, dict):
        for index, row in enumerate(complexity.get("strategies", [])):
            if not isinstance(row, dict):
                errors.append(f"complexity_benchmark.strategies[{index}] must be an object.")
                continue
            for field in (
                "matrix_build_seconds",
                "candidate_generation_seconds",
                "similarity_seconds",
                "neighbor_selection_seconds",
                "total_seconds",
                "estimated_peak_megabytes",
            ):
                if field in row:
                    errors.extend(
                        _finite_non_negative(
                            row[field],
                            f"complexity_benchmark.strategies[{index}].{field}",
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
            {
                "user_based_cosine",
                "user_based_jaccard",
                "user_based_pearson",
                "item_based_cosine",
                "item_based_jaccard",
                "item_based_pearson",
            }.issubset(model_types)
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
        "runtime_metrics_valid": metrics_ok,
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
