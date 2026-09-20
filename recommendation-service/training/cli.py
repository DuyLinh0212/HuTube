from __future__ import annotations

import argparse
import json
from datetime import UTC, datetime
from pathlib import Path
from typing import Any

import pandas as pd
import yaml

from app.config import SERVICE_ROOT
from app.data.mapping import build_mappings, encode_interactions
from app.data.movielens import export_unified_csv, load_ml100k, validate_ml100k
from app.model_registry import load_artifact_directory
from training.artifacts import (
    load_json,
    make_model_version,
    save_artifact,
    update_benchmark_pointer,
)
from training.comparison import generate_comparison_report
from training.config import TrainConfig, load_train_config
from training.evaluate import EvaluationResult, evaluate_model
from training.quality_gate import run_quality_gate, write_quality_gate
from training.reports import generate_reports
from training.trainer import MODEL_TYPES, ModelType, fit_both_models


def _load_artifact_config(artifact_dir: Path) -> TrainConfig:
    payload = yaml.safe_load((artifact_dir / "config.yaml").read_text(encoding="utf-8"))
    return TrainConfig.model_validate({**payload, "project_root": SERVICE_ROOT})


def _prepare_data(config: TrainConfig):
    dataset = load_ml100k(
        config.resolve(config.data.path),
        strict_counts=config.data.strict_counts,
        max_users=config.data.max_users,
    )
    export_unified_csv(
        dataset.interactions,
        config.resolve(config.data.processed_path),
    )
    mappings = build_mappings(
        dataset.interactions,
        item_ids=dataset.items["item_id"].astype(str).tolist(),
    )
    interactions = encode_interactions(dataset.interactions, mappings)
    return dataset, interactions, mappings


def _dataset_summary(dataset, interactions) -> dict[str, Any]:
    return {
        "source_ratings": dataset.source_summary.ratings,
        "source_users": dataset.source_summary.users,
        "source_items": dataset.source_summary.items,
        "genres": dataset.source_summary.genres,
        "active_ratings": dataset.active_summary.ratings,
        "active_users": dataset.active_summary.users,
        "active_items": dataset.active_summary.items,
        "observed_rows": len(interactions),
    }


def _evaluate_models(
    models: dict[ModelType, Any],
    interactions: pd.DataFrame,
    *,
    dataset,
    mappings,
    config: TrainConfig,
) -> dict[ModelType, EvaluationResult]:
    return {
        model_type: evaluate_model(
            model,
            interactions,
            mappings=mappings,
            items=dataset.items,
            genre_names=dataset.genre_names,
            k_values=config.evaluation.k,
            positive_rating_threshold=config.preference.positive_rating_threshold,
        )
        for model_type, model in models.items()
    }


def _comparison_summary(
    metrics: dict[ModelType, dict[str, Any]],
    *,
    k_values: list[int],
) -> dict[str, Any]:
    primary_metric = (
        "preference_alignment@10"
        if 10 in k_values
        else f"preference_alignment@{max(k_values)}"
    )
    values = {
        model_type: metrics[model_type].get(primary_metric)
        for model_type in MODEL_TYPES
    }
    available = {name: value for name, value in values.items() if value is not None}
    winner = max(available, key=available.get) if available else None
    return {
        "primaryMetric": primary_metric,
        "winner": winner,
        "values": values,
    }


def _metrics_payload(
    evaluations: dict[ModelType, EvaluationResult],
    *,
    config: TrainConfig,
) -> dict[str, Any]:
    model_metrics = {
        model_type: {"preference": evaluations[model_type].metrics}
        for model_type in MODEL_TYPES
    }
    return {
        "models": model_metrics,
        "comparison": _comparison_summary(
            {model_type: evaluations[model_type].metrics for model_type in MODEL_TYPES},
            k_values=config.evaluation.k,
        ),
        "evaluation_protocol": {
            "name": "preference_alignment",
            "uses_exact_item_holdout": False,
            "uses_genre_only_for_evaluation": True,
            "profile_source": "complete_observed_user_history",
        },
        "binary_behaviors": {
            "like": None,
            "dislike": None,
            "comment": None,
            "share": None,
        },
        "watch_ratio": None,
        "fallback_rate": None,
        "cold_start_rate": None,
    }


def command_validate_data(args: argparse.Namespace) -> int:
    summary = validate_ml100k(args.data_dir, strict_counts=not args.no_strict)
    print(json.dumps(summary.as_dict(), indent=2))
    return 0


def command_train(args: argparse.Namespace) -> int:
    config = load_train_config(args.config)
    dataset, interactions, mappings = _prepare_data(config)

    fitted = fit_both_models(interactions, config=config, mappings=mappings)
    models = {model_type: result.model for model_type, result in fitted.items()}
    evaluations = _evaluate_models(
        models,
        interactions,
        dataset=dataset,
        mappings=mappings,
        config=config,
    )
    metrics = _metrics_payload(evaluations, config=config)
    model_version = make_model_version(config)
    metadata = {
        "modelVersion": model_version,
        "trainedAt": datetime.now(UTC).isoformat(),
        "source": "MOVIELENS",
        "deployable": False,
        "dataset": "MovieLens 100K",
        "datasetSize": dataset.active_summary.ratings,
        "users": len(mappings.user_to_index),
        "items": len(mappings.item_to_index),
        "modelTypes": list(MODEL_TYPES),
        "similarity": config.model.similarity,
        "interactionMode": config.model.interaction_mode,
        "neighborCount": config.model.neighbor_count,
        "primaryMetric": metrics["comparison"]["primaryMetric"],
        "evaluationProtocol": metrics["evaluation_protocol"],
    }
    history = [
        {
            "model": model_type,
            "fit_seconds": fitted[model_type].fit_seconds,
            "neighbor_count": config.model.neighbor_count,
            "similarity": config.model.similarity,
            "interaction_mode": config.model.interaction_mode,
        }
        for model_type in MODEL_TYPES
    ]
    artifact_root = config.resolve(config.output.artifact_root)
    artifact_dir = save_artifact(
        artifact_root=artifact_root,
        model_version=model_version,
        models=models,
        config=config,
        mappings=mappings,
        fit_interactions=interactions,
        items=dataset.items,
        genre_names=dataset.genre_names,
        metrics=metrics,
        history=history,
        metadata=metadata,
    )
    report_dir = config.resolve(config.output.report_root) / model_version
    report = generate_reports(
        report_dir=report_dir,
        artifact_root=artifact_root,
        model_version=model_version,
        metrics=metrics,
        history=history,
        interactions=interactions,
        dataset_summary=_dataset_summary(dataset, interactions),
    )
    quality_gate = run_quality_gate(artifact_dir)
    write_quality_gate(quality_gate, artifact_dir / "quality_gate.json")
    write_quality_gate(quality_gate, report_dir / "quality_gate.json")
    if not quality_gate.passed:
        raise RuntimeError(
            "Artifact failed quality gate: " + "; ".join(quality_gate.errors)
        )
    update_benchmark_pointer(artifact_root, model_version)
    print(
        json.dumps(
            {
                "modelVersion": model_version,
                "artifact": str(artifact_dir),
                "report": str(report),
                "qualityGate": quality_gate.as_dict(),
                "comparison": metrics["comparison"],
            },
            ensure_ascii=False,
            indent=2,
        )
    )
    return 0


def _load_evaluation_context(artifact_dir: Path):
    config = _load_artifact_config(artifact_dir)
    dataset, generated_interactions, _generated_mappings = _prepare_data(config)
    loaded = load_artifact_directory(artifact_dir, model_type="item_based")
    frame = generated_interactions.drop(columns=["user_index", "item_index"])
    interactions = encode_interactions(frame, loaded.mappings)
    return config, dataset, interactions, loaded.mappings


def _evaluate_artifact(artifact_dir: Path):
    config, dataset, interactions, mappings = _load_evaluation_context(artifact_dir)
    results: dict[ModelType, EvaluationResult] = {}
    for model_type in MODEL_TYPES:
        loaded = load_artifact_directory(artifact_dir, model_type=model_type)
        results[model_type] = evaluate_model(
            loaded.model,
            interactions,
            mappings=mappings,
            items=dataset.items,
            genre_names=dataset.genre_names,
            k_values=config.evaluation.k,
            positive_rating_threshold=config.preference.positive_rating_threshold,
        )
    return config, dataset, interactions, mappings, results


def command_evaluate(args: argparse.Namespace) -> int:
    artifact_dir = Path(args.artifact).expanduser().resolve()
    config, _dataset, _interactions, _mappings, results = _evaluate_artifact(artifact_dir)
    metrics = {model_type: results[model_type].metrics for model_type in MODEL_TYPES}
    payload = {
        "models": {
            model_type: {"preference": metrics[model_type]}
            for model_type in MODEL_TYPES
        },
        "comparison": _comparison_summary(metrics, k_values=config.evaluation.k),
        "evaluation_protocol": {
            "name": "preference_alignment",
            "uses_exact_item_holdout": False,
            "uses_genre_only_for_evaluation": True,
            "profile_source": "complete_observed_user_history",
        },
    }
    output = artifact_dir / "metrics.recomputed.json"
    output.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps(payload, ensure_ascii=False, indent=2))
    return 0


def command_report(args: argparse.Namespace) -> int:
    artifact_dir = Path(args.artifact).expanduser().resolve()
    config = _load_artifact_config(artifact_dir)
    dataset, interactions, _mappings = _prepare_data(config)
    metadata = load_json(artifact_dir / "metadata.json")
    metrics = load_json(artifact_dir / "metrics.json")
    history = load_json(artifact_dir / "training_history.json")
    report_dir = config.resolve(config.output.report_root) / str(metadata["modelVersion"])
    output = generate_reports(
        report_dir=report_dir,
        artifact_root=config.resolve(config.output.artifact_root),
        model_version=str(metadata["modelVersion"]),
        metrics=metrics,
        history=history,
        interactions=interactions,
        dataset_summary=_dataset_summary(dataset, interactions),
    )
    print(output)
    return 0


def command_compare(args: argparse.Namespace) -> int:
    artifact_dir = Path(args.artifact).expanduser().resolve()
    config, _dataset, _interactions, _mappings, results = _evaluate_artifact(artifact_dir)
    metadata = load_json(artifact_dir / "metadata.json")
    report_dir = config.resolve(config.output.report_root) / str(metadata["modelVersion"])
    output = generate_comparison_report(
        report_dir=report_dir,
        model_version=str(metadata["modelVersion"]),
        model_metrics={model_type: results[model_type].metrics for model_type in MODEL_TYPES},
    )
    print(output)
    return 0


def command_quality_gate(args: argparse.Namespace) -> int:
    artifact_dir = Path(args.artifact).expanduser().resolve()
    result = run_quality_gate(artifact_dir)
    write_quality_gate(result, artifact_dir / "quality_gate.json")
    print(json.dumps(result.as_dict(), ensure_ascii=False, indent=2))
    return 0 if result.passed else 1


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="HuTube pure User-Based and Item-Based Collaborative Filtering pipeline"
    )
    subparsers = parser.add_subparsers(dest="command", required=True)

    validate = subparsers.add_parser("validate-data")
    validate.add_argument("--data-dir", required=True)
    validate.add_argument("--no-strict", action="store_true")
    validate.set_defaults(handler=command_validate_data)

    train = subparsers.add_parser("train")
    train.add_argument("--config", required=True)
    train.set_defaults(handler=command_train)

    evaluate = subparsers.add_parser("evaluate")
    evaluate.add_argument("--artifact", required=True)
    evaluate.set_defaults(handler=command_evaluate)

    report = subparsers.add_parser("report")
    report.add_argument("--artifact", required=True)
    report.set_defaults(handler=command_report)

    compare = subparsers.add_parser("compare")
    compare.add_argument("--artifact", required=True)
    compare.set_defaults(handler=command_compare)

    quality_gate = subparsers.add_parser("quality-gate")
    quality_gate.add_argument("--artifact", required=True)
    quality_gate.set_defaults(handler=command_quality_gate)
    return parser


def main() -> int:
    args = build_parser().parse_args()
    return int(args.handler(args))


if __name__ == "__main__":
    raise SystemExit(main())
