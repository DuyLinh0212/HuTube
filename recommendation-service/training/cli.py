from __future__ import annotations

import argparse
import json
from datetime import UTC, datetime
from pathlib import Path
from time import perf_counter
from typing import Any

import pandas as pd
import yaml

from app.config import SERVICE_ROOT
from app.data.mapping import build_mappings, encode_interactions
from app.data.movielens import export_unified_csv, load_ml100k, validate_ml100k
from app.data.split import temporal_split
from app.model_registry import load_artifact_directory
from app.recommenders.item_cf import ItemBasedCF
from training.artifacts import (
    load_json,
    make_model_version,
    save_artifact,
    update_benchmark_pointer,
)
from training.comparison import generate_comparison_report
from training.config import TrainConfig, load_train_config
from training.evaluate import evaluate_model
from training.item_cf import evaluate_item_cf
from training.quality_gate import run_quality_gate, write_quality_gate
from training.reports import generate_reports
from training.trainer import fit_final_model, resolve_device, train_with_validation


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
    split = temporal_split(
        dataset.interactions,
        train_ratio=config.data.split.train,
        validation_ratio=config.data.split.validation,
        test_ratio=config.data.split.test,
    )
    mappings = build_mappings(
        dataset.interactions,
        item_ids=dataset.items["item_id"].astype(str).tolist(),
    )
    split.train = encode_interactions(split.train, mappings)
    split.validation = encode_interactions(split.validation, mappings)
    split.test = encode_interactions(split.test, mappings)
    return dataset, split, mappings


def _dataset_summary(dataset, split) -> dict[str, Any]:
    return {
        "source_ratings": dataset.source_summary.ratings,
        "source_users": dataset.source_summary.users,
        "source_items": dataset.source_summary.items,
        "genres": dataset.source_summary.genres,
        "active_ratings": dataset.active_summary.ratings,
        "active_users": dataset.active_summary.users,
        "active_items": dataset.active_summary.items,
        "train_rows": len(split.train),
        "validation_rows": len(split.validation),
        "test_rows": len(split.test),
    }


def command_validate_data(args: argparse.Namespace) -> int:
    summary = validate_ml100k(args.data_dir, strict_counts=not args.no_strict)
    print(json.dumps(summary.as_dict(), indent=2))
    return 0


def command_train(args: argparse.Namespace) -> int:
    config = load_train_config(args.config)
    dataset, split, mappings = _prepare_data(config)
    selection = train_with_validation(
        split.train,
        split.validation,
        config=config,
        mappings=mappings,
        items=dataset.items,
        genre_names=dataset.genre_names,
    )
    validation = evaluate_model(
        selection.model,
        split.validation,
        split.train,
        mappings=mappings,
        items=dataset.items,
        genre_names=dataset.genre_names,
        k_values=config.evaluation.k,
        rating_threshold=config.relevance.rating_threshold,
        device=resolve_device(config),
        popularity_weight=config.ranking.popularity_weight,
    )
    fit_interactions = pd.concat([split.train, split.validation], ignore_index=True)
    final = fit_final_model(
        fit_interactions,
        config=config,
        mappings=mappings,
        items=dataset.items,
        genre_names=dataset.genre_names,
        epochs=selection.best_epoch,
    )
    test = evaluate_model(
        final.model,
        split.test,
        fit_interactions,
        mappings=mappings,
        items=dataset.items,
        genre_names=dataset.genre_names,
        k_values=config.evaluation.k,
        rating_threshold=config.relevance.rating_threshold,
        device=resolve_device(config),
        popularity_weight=config.ranking.popularity_weight,
    )
    metrics = {
        "validation": validation.metrics,
        "test": test.metrics,
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
        "bestEpoch": selection.best_epoch,
        "activeTasks": final.active_tasks,
        "primaryMetric": "ndcg@10",
        "validationNdcg10": validation.metrics.get("ndcg@10"),
        "testNdcg10": test.metrics.get("ndcg@10"),
        "testRecall10": test.metrics.get("recall@10"),
        "testRmse": test.metrics.get("rmse"),
        "ranking": {
            "popularityWeight": config.ranking.popularity_weight,
        },
    }
    artifact_root = config.resolve(config.output.artifact_root)
    artifact_dir = save_artifact(
        artifact_root=artifact_root,
        model_version=model_version,
        model=final.model,
        config=config,
        mappings=mappings,
        fit_interactions=fit_interactions,
        items=dataset.items,
        genre_names=dataset.genre_names,
        metrics=metrics,
        history=selection.history,
        metadata=metadata,
    )
    report_dir = config.resolve(config.output.report_root) / model_version
    report = generate_reports(
        report_dir=report_dir,
        artifact_root=artifact_root,
        model_version=model_version,
        metrics=metrics,
        history=selection.history,
        interactions=dataset.interactions,
        dataset_summary=_dataset_summary(dataset, split),
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
                "metrics": metrics["test"],
            },
            ensure_ascii=False,
            indent=2,
        )
    )
    return 0


def _artifact_evaluation(artifact_dir: Path):
    config = _load_artifact_config(artifact_dir)
    dataset, split, _generated_mappings = _prepare_data(config)
    loaded = load_artifact_directory(artifact_dir, device_name=config.training.device)
    mappings = loaded.mappings
    split.train = encode_interactions(
        split.train.drop(columns=["user_index", "item_index"]),
        mappings,
    )
    split.validation = encode_interactions(
        split.validation.drop(columns=["user_index", "item_index"]),
        mappings,
    )
    split.test = encode_interactions(
        split.test.drop(columns=["user_index", "item_index"]),
        mappings,
    )
    fit_interactions = pd.concat([split.train, split.validation], ignore_index=True)
    result = evaluate_model(
        loaded.model,
        split.test,
        fit_interactions,
        mappings=mappings,
        items=dataset.items,
        genre_names=dataset.genre_names,
        k_values=config.evaluation.k,
        rating_threshold=config.relevance.rating_threshold,
        device=loaded.device,
        popularity_weight=config.ranking.popularity_weight,
    )
    return config, dataset, split, loaded, result


def command_evaluate(args: argparse.Namespace) -> int:
    artifact_dir = Path(args.artifact).expanduser().resolve()
    _config, _dataset, _split, _loaded, result = _artifact_evaluation(artifact_dir)
    output = artifact_dir / "metrics.recomputed.json"
    output.write_text(
        json.dumps(result.metrics, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )
    print(json.dumps(result.metrics, ensure_ascii=False, indent=2))
    return 0


def command_report(args: argparse.Namespace) -> int:
    artifact_dir = Path(args.artifact).expanduser().resolve()
    config, dataset, split, loaded, _result = _artifact_evaluation(artifact_dir)
    metrics = load_json(artifact_dir / "metrics.json")
    history = load_json(artifact_dir / "training_history.json")
    report_dir = config.resolve(config.output.report_root) / str(
        loaded.metadata["modelVersion"]
    )
    output = generate_reports(
        report_dir=report_dir,
        artifact_root=config.resolve(config.output.artifact_root),
        model_version=str(loaded.metadata["modelVersion"]),
        metrics=metrics,
        history=history,
        interactions=dataset.interactions,
        dataset_summary=_dataset_summary(dataset, split),
    )
    print(output)
    return 0


def command_quality_gate(args: argparse.Namespace) -> int:
    artifact_dir = Path(args.artifact).expanduser().resolve()
    result = run_quality_gate(artifact_dir)
    write_quality_gate(result, artifact_dir / "quality_gate.json")
    print(json.dumps(result.as_dict(), ensure_ascii=False, indent=2))
    return 0 if result.passed else 1


def command_compare_item_cf(args: argparse.Namespace) -> int:
    artifact_dir = Path(args.artifact).expanduser().resolve()
    config, dataset, split, loaded, mbmf_result = _artifact_evaluation(artifact_dir)
    fit_interactions = pd.concat([split.train, split.validation], ignore_index=True)
    started = perf_counter()
    item_cf = ItemBasedCF.fit(
        fit_interactions,
        user_count=len(loaded.mappings.user_to_index),
        item_count=len(loaded.mappings.item_to_index),
        neighbor_count=args.neighbors,
    )
    fit_seconds = perf_counter() - started
    started = perf_counter()
    item_cf_result = evaluate_item_cf(
        item_cf,
        split.test,
        fit_interactions,
        mappings=loaded.mappings,
        items=dataset.items,
        genre_names=dataset.genre_names,
        k_values=config.evaluation.k,
        rating_threshold=config.relevance.rating_threshold,
    )
    evaluation_seconds = perf_counter() - started
    report_dir = config.resolve(config.output.report_root) / str(
        loaded.metadata["modelVersion"]
    )
    output = generate_comparison_report(
        report_dir=report_dir,
        model_version=str(loaded.metadata["modelVersion"]),
        mbmf_metrics=mbmf_result.metrics,
        item_cf_metrics=item_cf_result.metrics,
        neighbor_count=item_cf.neighbor_count,
    )
    print(
        json.dumps(
            {
                "modelVersion": loaded.metadata["modelVersion"],
                "neighbors": item_cf.neighbor_count,
                "fitSeconds": fit_seconds,
                "evaluationSeconds": evaluation_seconds,
                "mbmf": mbmf_result.metrics,
                "itemCf": item_cf_result.metrics,
                "report": str(output),
            },
            ensure_ascii=False,
            indent=2,
        )
    )
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="HuTube MBMF training pipeline")
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

    quality_gate = subparsers.add_parser("quality-gate")
    quality_gate.add_argument("--artifact", required=True)
    quality_gate.set_defaults(handler=command_quality_gate)

    compare = subparsers.add_parser("compare-item-cf")
    compare.add_argument("--artifact", required=True)
    compare.add_argument("--neighbors", type=int, default=50)
    compare.set_defaults(handler=command_compare_item_cf)
    return parser


def main() -> int:
    args = build_parser().parse_args()
    return int(args.handler(args))


if __name__ == "__main__":
    raise SystemExit(main())
