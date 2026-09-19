from __future__ import annotations

import json
from dataclasses import dataclass
from pathlib import Path

import numpy as np
import torch

from app.config import Settings
from app.data.mapping import IndexMappings
from app.recommenders.mbmf import MultiBehaviorMF


@dataclass(slots=True)
class LoadedModel:
    model: MultiBehaviorMF
    mappings: IndexMappings
    index_to_item: list[str]
    seen_indptr: np.ndarray
    seen_indices: np.ndarray
    metadata: dict
    item_metadata: dict
    artifact_dir: Path
    device: torch.device
    item_popularity: np.ndarray | None = None
    popularity_weight: float = 0.0

    def seen_items(self, user_index: int) -> np.ndarray:
        start = int(self.seen_indptr[user_index])
        end = int(self.seen_indptr[user_index + 1])
        return self.seen_indices[start:end]


def _read_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def load_artifact_directory(
    artifact_dir: str | Path,
    *,
    device_name: str = "cpu",
) -> LoadedModel:
    path = Path(artifact_dir).expanduser().resolve()
    required = (
        "model.pt",
        "metadata.json",
        "user_index.json",
        "item_index.json",
        "item_metadata.json",
        "seen_items.npz",
    )
    missing = [name for name in required if not (path / name).is_file()]
    if missing:
        raise FileNotFoundError(f"Artifact {path} is incomplete: {', '.join(missing)}")
    device = torch.device(device_name)
    checkpoint = torch.load(path / "model.pt", map_location=device, weights_only=True)
    model = MultiBehaviorMF(
        users=int(checkpoint["user_count"]),
        items=int(checkpoint["item_count"]),
        embedding_dimension=int(checkpoint["embedding_dimension"]),
    )
    model.load_state_dict(checkpoint["state_dict"])
    model.to(device)
    model.eval()
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
    popularity_path = path / "item_popularity.json"
    item_popularity = (
        np.asarray(json.loads(popularity_path.read_text(encoding="utf-8")), dtype=np.float32)
        if popularity_path.is_file()
        else None
    )
    ranking = _read_json(path / "metadata.json").get("ranking", {})
    return LoadedModel(
        model=model,
        mappings=mappings,
        index_to_item=mappings.index_to_item,
        seen_indptr=seen["indptr"],
        seen_indices=seen["indices"],
        metadata=_read_json(path / "metadata.json"),
        item_metadata=_read_json(path / "item_metadata.json"),
        artifact_dir=path,
        device=device,
        item_popularity=item_popularity,
        popularity_weight=float(ranking.get("popularityWeight", 0.0)),
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
                device_name=self.settings.device,
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
