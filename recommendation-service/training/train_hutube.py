#!/usr/bin/env python3
"""Train deployed Item-Based Cosine from an explicit interaction CSV.

The six-variant local benchmark remains in ``training/train.py``. Production
never manufactures interaction data or reads the retired bot simulator.
"""

from __future__ import annotations

import argparse
import hashlib
import io
import sys
from datetime import UTC, datetime
from pathlib import Path
from uuid import uuid4

import pandas as pd

SERVICE_ROOT = Path(__file__).resolve().parents[1]
if str(SERVICE_ROOT) not in sys.path:
    sys.path.insert(0, str(SERVICE_ROOT))

from app.data.mapping import build_mappings, encode_interactions  # noqa: E402
from training.artifacts import save_artifact  # noqa: E402
from training.config import TrainConfig  # noqa: E402
from training.trainer import fit_model  # noqa: E402

REQUIRED_COLUMNS = {"user_id", "video_id", "score"}


def train_csv_bytes(csv_bytes: bytes, artifact_root: Path, *, csv_key: str,
                    csv_sha256: str) -> Path:
    if hashlib.sha256(csv_bytes).hexdigest() != csv_sha256:
        raise ValueError("CSV SHA-256 does not match the requested snapshot.")
    df = pd.read_csv(io.BytesIO(csv_bytes), dtype={"user_id": str, "video_id": str})
    if not REQUIRED_COLUMNS.issubset(df.columns):
        raise ValueError("CSV requires user_id, video_id and score columns.")
    if df.empty or df[["user_id", "video_id"]].isna().any().any():
        raise ValueError("Interaction matrix is empty or contains missing IDs.")
    if df.duplicated(["user_id", "video_id"]).any():
        raise ValueError("Interaction matrix contains duplicate user-video pairs.")
    df["rating"] = pd.to_numeric(df["score"], errors="raise")
    if not df["rating"].between(1.0, 5.0).all():
        raise ValueError("Interaction scores must be between 1 and 5.")
    df["item_id"] = df["video_id"]
    users = df["user_id"].nunique()
    items = df["item_id"].nunique()
    if users < 2 or items < 2 or len(df) < 3:
        raise ValueError("Item-Based CF needs at least 2 users, 2 videos and 3 interactions.")
    # Leave memory for pandas, archive creation and the currently serving model.
    estimated_bytes = users * items * 16 + items * items * 32
    if estimated_bytes > 160 * 1024 * 1024:
        raise ValueError("Matrix exceeds the configured 160 MiB training budget.")

    mappings = build_mappings(df)
    encoded = encode_interactions(df, mappings)
    config = TrainConfig(
        project_root=SERVICE_ROOT,
        data={"path": Path("data/processed"), "processed_path": Path("data/processed/unified.csv")},
        model={"similarities": ["cosine"], "interaction_mode": "rating", "neighbor_count": 50},
        output={"artifact_root": artifact_root, "report_root": Path("reports")},
    )
    fitted = fit_model("item_based_cosine", encoded, config=config, mappings=mappings)
    version = (
        f"cf_hutube_{datetime.now(UTC).strftime('%Y%m%dT%H%M%SZ')}"
        f"_{csv_sha256[:12]}_{uuid4().hex[:8]}"
    )
    items_frame = pd.DataFrame({"item_id": list(mappings.item_to_index),
                                "title": list(mappings.item_to_index)})
    metadata = {"modelVersion": version, "source": "HUTUBE", "deployable": True,
                "trainedAt": datetime.now(UTC).isoformat(), "usersCount": users,
                "itemsCount": items, "interactionsCount": len(df),
                "csvKey": csv_key, "csvSha256": csv_sha256}
    return save_artifact(
        artifact_root=artifact_root, model_version=version,
        models={"item_based_cosine": fitted.model}, config=config,
        mappings=mappings, fit_interactions=encoded, items=items_frame,
        genre_names=[], metrics={"totalInteractions": len(df)},
        history=[{"model": "item_based_cosine", "fit_seconds": fitted.fit_seconds}],
        metadata=metadata,
    )


def train_hutube_model(matrix_csv_path: str | Path | None = None,
                       artifact_root: Path | None = None) -> Path:
    if not matrix_csv_path or not Path(matrix_csv_path).is_file():
        raise ValueError("An existing --matrix-csv file is required; no sample data is generated.")
    raw = Path(matrix_csv_path).read_bytes()
    return train_csv_bytes(raw, artifact_root or SERVICE_ROOT / "data" / "artifacts",
                           csv_key=str(matrix_csv_path),
                           csv_sha256=hashlib.sha256(raw).hexdigest())


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Train HuTube Item-Based Cosine from CSV")
    parser.add_argument("--matrix-csv", required=True)
    args = parser.parse_args()
    print(train_hutube_model(args.matrix_csv))
