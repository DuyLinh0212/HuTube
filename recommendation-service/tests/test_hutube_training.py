from __future__ import annotations

import hashlib
import json

import pytest

from training.train_hutube import train_csv_bytes, train_hutube_model


def test_missing_matrix_never_generates_sample_data(tmp_path) -> None:
    with pytest.raises(ValueError, match="existing --matrix-csv"):
        train_hutube_model(tmp_path / "missing.csv", tmp_path / "artifacts")


def test_empty_matrix_is_rejected(tmp_path) -> None:
    raw = b"user_id,video_id,score\n"
    with pytest.raises(ValueError, match="empty"):
        train_csv_bytes(raw, tmp_path, csv_key="collaborative_cf/test.csv",
                        csv_sha256=hashlib.sha256(raw).hexdigest())


def test_hash_mismatch_is_rejected(tmp_path) -> None:
    raw = b"user_id,video_id,score\nu1,v1,1\n"
    with pytest.raises(ValueError, match="SHA-256"):
        train_csv_bytes(raw, tmp_path, csv_key="collaborative_cf/test.csv",
                        csv_sha256="0" * 64)


def test_train_only_item_based_cosine(tmp_path) -> None:
    raw = (b"user_id,video_id,score\n"
           b"u1,v1,1\nu1,v2,0.8\nu2,v1,0.8\nu2,v2,1\n")
    folder = train_csv_bytes(raw, tmp_path, csv_key="collaborative_cf/test.csv",
                             csv_sha256=hashlib.sha256(raw).hexdigest())
    assert (folder / "item_based_cosine.npz").is_file()
    assert not (folder / "user_based_cosine.npz").exists()
    assert (folder / "seen_items.npz").is_file()


def test_weighted_score_configuration_is_persisted(tmp_path) -> None:
    raw = (b"user_id,video_id,score\n"
           b"u1,v1,1\nu1,v2,0.8\nu2,v1,0.8\nu2,v2,1\n")
    folder = train_csv_bytes(
        raw,
        tmp_path,
        csv_key="collaborative_cf/test.csv",
        csv_sha256=hashlib.sha256(raw).hexdigest(),
        score_aggregation={
            "mode": "weighted",
            "weights": {"rating": 3, "like": 1, "watch": 2},
        },
    )
    metadata = json.loads((folder / "metadata.json").read_text())
    assert metadata["scoreAggregation"]["mode"] == "weighted"
    assert metadata["scoreAggregation"]["weights"]["rating"] == 3
    assert metadata["scoreAggregation"]["weights"]["dislike"] == 0
