from __future__ import annotations

import json
from dataclasses import dataclass
from pathlib import Path
from typing import Literal

import numpy as np

from app.config import Settings
from app.data.mapping import IndexMappings
from app.recommenders.base import CollaborativeFilter
from app.recommenders.item_cf import ItemBasedCF
from app.recommenders.user_cf import UserBasedCF

ModelType = Literal[
    "user_based",
    "item_based",
    "user_based_cosine",
    "user_based_jaccard",
    "user_based_pearson",
    "item_based_cosine",
    "item_based_jaccard",
    "item_based_pearson",
]


@dataclass(slots=True)
class LoadedModel:
    model: CollaborativeFilter
    model_type: ModelType
    mappings: IndexMappings
    index_to_item: list[str]
    seen_indptr: np.ndarray
    seen_indices: np.ndarray
    metadata: dict
    item_metadata: dict
    artifact_dir: Path

    def seen_items(self, user_index: int) -> np.ndarray:
        start = int(self.seen_indptr[user_index])
        end = int(self.seen_indptr[user_index + 1])
        return self.seen_indices[start:end]


def _read_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def _validate_model_type(value: str) -> ModelType:
    allowed = {
        "user_based",
        "item_based",
        "user_based_cosine",
        "user_based_jaccard",
        "user_based_pearson",
        "item_based_cosine",
        "item_based_jaccard",
        "item_based_pearson",
    }
    if value not in allowed:
        raise ValueError("Unsupported model_type.")
    return value  # type: ignore[return-value]


def _canonical_model_type(value: ModelType) -> str:
    return f"{value}_cosine" if value in {"user_based", "item_based"} else value


def load_artifact_directory(
    artifact_dir: str | Path,
    *,
    model_type: str = "item_based",
    device_name: str | None = None,
) -> LoadedModel:
    """Load one of the two pure-CF models from a shared artifact."""
    del device_name  # Kept as a harmless compatibility argument for old callers.
    selected_type = _validate_model_type(model_type)
    canonical_type = _canonical_model_type(selected_type)
    path = Path(artifact_dir).expanduser().resolve()
    model_file = path / f"{canonical_type}.npz"
    if not model_file.is_file() and selected_type in {"user_based", "item_based"}:
        model_file = path / f"{selected_type}.npz"
    required = (
        model_file.name,
        "metadata.json",
        "user_index.json",
        "item_index.json",
        "item_metadata.json",
        "seen_items.npz",
    )
    missing = [name for name in required if not (path / name).is_file()]
    if missing:
        raise FileNotFoundError(f"Artifact {path} is incomplete: {', '.join(missing)}")

    model = (
        UserBasedCF.load_npz(model_file)
        if canonical_type.startswith("user_based")
        else ItemBasedCF.load_npz(model_file)
    )
    user_to_index = {
        str(key): int(value)
        for key, value in _read_json(path / "user_index.json").items()
    }
    item_to_index = {
        str(key): int(value)
        for key, value in _read_json(path / "item_index.json").items()
    }
    mappings = IndexMappings(user_to_index=user_to_index, item_to_index=item_to_index)
    seen = np.load(path / "seen_items.npz")
    return LoadedModel(
        model=model,
        model_type=selected_type,
        mappings=mappings,
        index_to_item=mappings.index_to_item,
        seen_indptr=np.asarray(seen["indptr"], dtype=np.int64),
        seen_indices=np.asarray(seen["indices"], dtype=np.int64),
        metadata=_read_json(path / "metadata.json"),
        item_metadata=_read_json(path / "item_metadata.json"),
        artifact_dir=path,
    )


class ModelRegistry:
    def __init__(self, settings: Settings) -> None:
        self.settings = settings
        self.loaded: LoadedModel | None = None
        self.load_error: str | None = None

    def _resolve_artifact(self) -> Path:
        root = self.settings.resolved_model_storage_path
        version = self.settings.model_version
        if version in {"benchmark-latest", "latest"}:
            pointer = root / f"{version}.json"
            payload = _read_json(pointer)
            return (root / str(payload["path"])).resolve()
        return (root / version).resolve()

    def load(self) -> None:
        try:
            loaded = load_artifact_directory(
                self._resolve_artifact(),
                model_type=self.settings.model_type,
            )
            source = str(loaded.metadata.get("source", ""))
            deployable = bool(loaded.metadata.get("deployable", False))
            if self.settings.app_env.lower() == "production" and not deployable:
                raise RuntimeError("Production refuses an artifact marked deployable=false.")
            if source == "MOVIELENS" and not self.settings.allow_benchmark_model:
                raise RuntimeError(
                    "MovieLens artifact requires ALLOW_BENCHMARK_MODEL=true."
                )
            self.loaded = loaded
            self.load_error = None
        except Exception as exc:
            self.loaded = None
            self.load_error = str(exc)
