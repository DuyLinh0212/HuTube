from __future__ import annotations

import json

from training.quality_gate import REQUIRED_ARTIFACT_FILES, run_quality_gate


def test_quality_gate_accepts_complete_safe_benchmark(tmp_path) -> None:
    artifact = tmp_path / "model"
    artifact.mkdir()
    for name in REQUIRED_ARTIFACT_FILES:
        (artifact / name).write_bytes(b"placeholder")
    (artifact / "metadata.json").write_text(
        json.dumps(
            {
                "modelVersion": "mbmf_test",
                "source": "MOVIELENS",
                "deployable": False,
            }
        ),
        encoding="utf-8",
    )
    (artifact / "metrics.json").write_text(
        json.dumps({"test": {"ndcg@10": 0.4, "rmse": 1.1}}),
        encoding="utf-8",
    )

    result = run_quality_gate(artifact)

    assert result.passed
    assert not result.errors


def test_quality_gate_rejects_invalid_ranking_metric(tmp_path) -> None:
    artifact = tmp_path / "model"
    artifact.mkdir()
    for name in REQUIRED_ARTIFACT_FILES:
        (artifact / name).write_bytes(b"placeholder")
    (artifact / "metadata.json").write_text(
        '{"modelVersion":"mbmf_test","source":"MOVIELENS","deployable":false}',
        encoding="utf-8",
    )
    (artifact / "metrics.json").write_text(
        '{"test":{"ndcg@10":1.5}}',
        encoding="utf-8",
    )

    result = run_quality_gate(artifact)

    assert not result.passed
    assert "ndcg@10 must be in [0, 1]." in result.errors


def test_quality_gate_requires_popularity_artifact_when_enabled(tmp_path) -> None:
    artifact = tmp_path / "model"
    artifact.mkdir()
    for name in REQUIRED_ARTIFACT_FILES:
        (artifact / name).write_bytes(b"placeholder")
    (artifact / "metadata.json").write_text(
        '{"modelVersion":"mbmf_test","source":"MOVIELENS",'
        '"deployable":false,"ranking":{"popularityWeight":0.2}}',
        encoding="utf-8",
    )
    (artifact / "metrics.json").write_text(
        '{"test":{"ndcg@10":0.2}}',
        encoding="utf-8",
    )

    result = run_quality_gate(artifact)

    assert not result.passed
    assert "item_popularity.json" in result.errors[0]
