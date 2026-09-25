from __future__ import annotations

import argparse
import json
from datetime import UTC, datetime
from pathlib import Path
from typing import Any

import yaml

from app.config import SERVICE_ROOT
from app.data.mapping import build_mappings, encode_interactions
from app.data.movielens import export_unified_csv, load_ml100k, validate_ml100k
from training.artifacts import (
    load_json,
    make_model_version,
    save_artifact,
    update_benchmark_pointer,
)
from training.comparison import generate_comparison_report
from training.complexity import benchmark_item_based_strategies
from training.config import TrainConfig, load_train_config
from training.quality_gate import run_quality_gate, write_quality_gate
from training.reports import generate_reports
from training.trainer import fit_all_models


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


def _runtime_payload(history: list[dict[str, Any]]) -> dict[str, Any]:
    models = {
        str(row["model"]): {"fit_seconds": float(row["fit_seconds"])}
        for row in history
    }
    return {
        "runtime": {
            "models": models,
            "total_fit_seconds": sum(
                float(row["fit_seconds"]) for row in history
            ),
        },
    }


def command_validate_data(args: argparse.Namespace) -> int:
    summary = validate_ml100k(args.data_dir, strict_counts=not args.no_strict)
    print(json.dumps(summary.as_dict(), indent=2))
    return 0


def command_train(args: argparse.Namespace) -> int:
    config = load_train_config(args.config)
    dataset, interactions, mappings = _prepare_data(config)

    fitted = fit_all_models(interactions, config=config, mappings=mappings)
    models = {model_type: result.model for model_type, result in fitted.items()}
    history = [
        {
            "model": model_type,
            "family": model_type.rsplit("_", 1)[0],
            "similarity": model_type.rsplit("_", 1)[1],
            "fit_seconds": fitted[model_type].fit_seconds,
            "neighbor_count": config.model.neighbor_count,
            "interaction_mode": config.model.interaction_mode,
        }
        for model_type in fitted
    ]
    metrics = _runtime_payload(history)
    if config.benchmark.enabled:
        metrics["complexity_benchmark"] = benchmark_item_based_strategies(
            interactions,
            items=dataset.items,
            genre_names=dataset.genre_names,
            mappings=mappings,
            similarity=config.benchmark.similarity,
            interaction_mode=config.model.interaction_mode,
            neighbor_count=config.model.neighbor_count,
        )
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
        "modelTypes": list(fitted),
        "modelFamilies": ["user_based", "item_based"],
        "similarities": config.model.selected_similarities,
        "interactionMode": config.model.interaction_mode,
        "neighborCount": config.model.neighbor_count,
        "complexityBenchmark": (
            metrics.get("complexity_benchmark", {}).get("protocol")
            if isinstance(metrics.get("complexity_benchmark"), dict)
            else None
        ),
        "reportScope": "runtime_only",
    }
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
                "runtime": metrics["runtime"],
            },
            ensure_ascii=False,
            indent=2,
        )
    )
    return 0


def command_evaluate(args: argparse.Namespace) -> int:
    artifact_dir = Path(args.artifact).expanduser().resolve()
    metadata = load_json(artifact_dir / "metadata.json")
    history = load_json(artifact_dir / "training_history.json")
    payload = {
        "modelVersion": metadata.get("modelVersion"),
        **_runtime_payload(history),
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
    metadata = load_json(artifact_dir / "metadata.json")
    config = _load_artifact_config(artifact_dir)
    history = load_json(artifact_dir / "training_history.json")
    report_dir = config.resolve(config.output.report_root) / str(metadata["modelVersion"])
    output = generate_comparison_report(
        report_dir=report_dir,
        model_version=str(metadata["modelVersion"]),
        model_metrics={
            str(row["model"]): {"fit_seconds": float(row["fit_seconds"])}
            for row in history
        },
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
