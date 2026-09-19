from __future__ import annotations

import hashlib
import json
from datetime import UTC, datetime
from pathlib import Path
from typing import Any

import pandas as pd
import torch
import yaml

from app.data.mapping import IndexMappings, build_seen_csr, save_seen_csr
from app.ranking import item_popularity_counts
from app.recommenders.mbmf import MultiBehaviorMF
from training.config import TrainConfig


def _write_json(path: Path, payload: Any) -> None:
    path.write_text(
        json.dumps(payload, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )


def make_model_version(config: TrainConfig) -> str:
    payload = config.model_dump(mode="json", exclude={"project_root"})
    digest = hashlib.sha256(
        json.dumps(payload, sort_keys=True).encode("utf-8")
    ).hexdigest()[:8]
    timestamp = datetime.now(UTC).strftime("%Y%m%dT%H%M%SZ")
    return f"mbmf_ml100k_{timestamp}_{digest}"


def save_artifact(
    *,
    artifact_root: Path,
    model_version: str,
    model: MultiBehaviorMF,
    config: TrainConfig,
    mappings: IndexMappings,
    fit_interactions: pd.DataFrame,
    items: pd.DataFrame,
    genre_names: list[str],
    metrics: dict[str, Any],
    history: list[dict[str, Any]],
    metadata: dict[str, Any],
) -> Path:
    artifact_dir = artifact_root / model_version
    artifact_dir.mkdir(parents=True, exist_ok=False)
    torch.save(
        {
            "state_dict": model.state_dict(),
            "user_count": model.user_count,
            "item_count": model.item_count,
            "embedding_dimension": model.embedding_dimension,
        },
        artifact_dir / "model.pt",
    )
    config_payload = config.model_dump(mode="json", exclude={"project_root"})
    (artifact_dir / "config.yaml").write_text(
        yaml.safe_dump(config_payload, allow_unicode=True, sort_keys=False),
        encoding="utf-8",
    )
    _write_json(artifact_dir / "metrics.json", metrics)
    _write_json(artifact_dir / "metadata.json", metadata)
    _write_json(artifact_dir / "training_history.json", history)
    _write_json(artifact_dir / "user_index.json", mappings.user_to_index)
    _write_json(artifact_dir / "item_index.json", mappings.item_to_index)

    item_metadata: dict[str, dict[str, Any]] = {}
    for _, row in items.iterrows():
        item_id = str(row["item_id"])
        item_metadata[item_id] = {
            "title": str(row["title"]),
            "genres": [genre for genre in genre_names if int(row[genre]) == 1],
        }
    _write_json(artifact_dir / "item_metadata.json", item_metadata)
    _write_json(
        artifact_dir / "item_popularity.json",
        item_popularity_counts(
            fit_interactions,
            item_count=len(mappings.item_to_index),
        ).astype(int).tolist(),
    )
    indptr, indices = build_seen_csr(fit_interactions, mappings)
    save_seen_csr(artifact_dir / "seen_items.npz", indptr, indices)

    return artifact_dir


def update_benchmark_pointer(artifact_root: Path, model_version: str) -> Path:
    artifact_root.mkdir(parents=True, exist_ok=True)
    pointer = artifact_root / "benchmark-latest.json"
    _write_json(
        pointer,
        {
            "modelVersion": model_version,
            "path": model_version,
            "source": "MOVIELENS",
            "deployable": False,
        },
    )
    return pointer


def load_json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))
