from __future__ import annotations

import hashlib
import io
import json
import threading
import zipfile
from dataclasses import dataclass
from pathlib import Path
from tempfile import TemporaryDirectory
from typing import Any, Literal

import numpy as np
from botocore.exceptions import ClientError

from app.config import Settings
from app.data.mapping import IndexMappings
from app.r2_store import R2Store
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
        self.manifest: dict | None = None
        self.update_lock = threading.Lock()
        self.update_task = None
        self.update_jobs: dict[str, dict] = {}

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
            if self.settings.r2_account_id:
                store = R2Store(self.settings)
                manifest = store.read_json("collaborative_cf/active.json")
                if manifest is None:
                    raise FileNotFoundError("No active collaborative CF manifest exists on R2.")
                if self.loaded is not None and self.manifest == manifest:
                    self.load_error = None
                    return
                loaded = self._load_archive(store, manifest)
                self.loaded = loaded
                self.manifest = manifest
                self.load_error = None
                return
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
            # A failed reload must leave the previous in-memory model serving.
            self.load_error = str(exc)

    def _load_archive(self, store: R2Store, manifest: dict) -> LoadedModel:
        archive = store.read(str(manifest["artifactKey"]))
        if hashlib.sha256(archive).hexdigest() != manifest["artifactSha256"]:
            raise ValueError("Active artifact SHA-256 mismatch.")
        with TemporaryDirectory() as folder:
            root = Path(folder)
            with zipfile.ZipFile(io.BytesIO(archive)) as zf:
                for name in zf.namelist():
                    if (
                        name.startswith("/")
                        or ".." in Path(name).parts
                        or "/" in name
                        or "\\" in name
                    ):
                        raise ValueError("Unsafe artifact archive entry.")
                zf.extractall(root)
            loaded = load_artifact_directory(root, model_type="item_based_cosine")
        if (loaded.metadata.get("modelVersion") != manifest["modelVersion"]
            or loaded.metadata.get("csvKey") != manifest["csvKey"]
            or loaded.metadata.get("csvSha256") != manifest["csvSha256"]
            or loaded.metadata.get("modelAlgorithm", "item_based")
            != manifest.get("modelAlgorithm", "item_based")
            or loaded.metadata.get("scoreAggregation") != manifest.get("scoreAggregation")
                or loaded.metadata.get("deployable") is not True
                or loaded.metadata.get("source") != "HUTUBE"):
            raise ValueError("Active artifact metadata does not match the manifest.")
        return loaded

    def train_from_r2(
        self,
        csv_key: str,
        csv_sha256: str,
        score_aggregation: dict[str, Any] | None = None,
        model_algorithm: str = "item_based",
    ) -> dict:
        from datetime import UTC, datetime

        from training.train_hutube import train_csv_bytes

        if not csv_key.startswith("collaborative_cf/") or not csv_key.endswith(".csv"):
            raise ValueError("CSV key must be inside collaborative_cf/ and end in .csv.")
        if len(csv_sha256) != 64:
            raise ValueError("A full SHA-256 digest is required.")
        if not self.update_lock.acquire(blocking=False):
            raise RuntimeError("A model update is already running.")
        lease = None
        store = None
        try:
            store = R2Store(self.settings)
            lease = store.acquire_training_lease()
            csv = store.read(csv_key)
            if len(csv) > 32 * 1024 * 1024:
                raise ValueError("CSV exceeds the 32 MiB training limit.")
            with TemporaryDirectory() as folder:
                artifact_dir = train_csv_bytes(csv, Path(folder), csv_key=csv_key,
                                               csv_sha256=csv_sha256,
                                               score_aggregation=score_aggregation,
                                               model_algorithm=model_algorithm)
                packed = io.BytesIO()
                with zipfile.ZipFile(packed, "w", compression=zipfile.ZIP_DEFLATED) as zf:
                    for file in artifact_dir.iterdir():
                        if file.is_file():
                            zf.write(file, file.name)
                archive = packed.getvalue()
                if len(archive) > 64 * 1024 * 1024:
                    raise ValueError("Artifact exceeds the 64 MiB upload limit.")
                metadata = json.loads((artifact_dir / "metadata.json").read_text(encoding="utf-8"))
                manifest = {
                    "modelVersion": metadata["modelVersion"], "csvKey": csv_key,
                    "csvSha256": csv_sha256,
                    "artifactKey": f"collaborative_cf/artifacts/{metadata['modelVersion']}.zip",
                    "artifactSha256": hashlib.sha256(archive).hexdigest(),
                    "updatedAt": datetime.now(UTC).isoformat(),
                    "modelAlgorithm": metadata.get("modelAlgorithm", "item_based"),
                    "scoreAggregation": metadata.get("scoreAggregation"),
                }
                store.write(manifest["artifactKey"], archive, "application/zip")
                preview = self._load_archive(store, manifest)
                # active.json is the publication point. Before this write the old
                # model remains authoritative, including after process restarts.
                lease = (lease[0], store.renew_training_lease(*lease))
                store.write_json("collaborative_cf/active.json", manifest)
                self.loaded = preview
                self.manifest = manifest
                self.load_error = None
                return manifest
        finally:
            if store is not None and lease is not None:
                try:
                    store.release_training_lease(*lease)
                except Exception:
                    # A newer lease owner must never be overwritten during cleanup.
                    pass
            self.update_lock.release()

    def create_job(self, job_id: str, value: dict) -> bool:
        """Only one replica may own a new job ID and schedule its training."""
        try:
            R2Store(self.settings).compare_write_json(
                f"collaborative_cf/jobs/{job_id}.json", value, None
            )
        except ClientError as exc:
            if exc.response.get("Error", {}).get("Code") in {
                "PreconditionFailed", "412", "ConditionalRequestConflict", "409"
            }:
                return False
            raise
        self.update_jobs[job_id] = value
        return True

    def record_job(self, job_id: str, value: dict) -> None:
        R2Store(self.settings).write_json(f"collaborative_cf/jobs/{job_id}.json", value)
        self.update_jobs[job_id] = value

    def get_job(self, job_id: str) -> dict | None:
        from uuid import UUID

        try:
            job_id = str(UUID(job_id))
        except ValueError:
            return None
        store = R2Store(self.settings)
        job = store.read_json(f"collaborative_cf/jobs/{job_id}.json")
        if job and job["status"] == "running":
            active = store.read_json("collaborative_cf/active.json")
            from training.train_hutube import normalize_score_aggregation
            from training.trainer import normalize_model_algorithm

            if (active and all(active.get(key) == job.get(key) for key in ("csvKey", "csvSha256"))
                    and normalize_model_algorithm(active.get("modelAlgorithm"))
                    == normalize_model_algorithm(job.get("modelAlgorithm"))
                    and normalize_score_aggregation(active.get("scoreAggregation"))
                    == normalize_score_aggregation(job.get("scoreAggregation"))):
                job = {**job, "status": "completed", "manifest": active}
                self.record_job(job_id, job)
        return job

    def refresh(self) -> None:
        if not self.update_lock.acquire(blocking=False):
            return
        try:
            self.load()
        finally:
            self.update_lock.release()
