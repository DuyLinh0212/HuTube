from __future__ import annotations

import json

from training.quality_gate import REQUIRED_ARTIFACT_FILES, run_quality_gate


def _complete_artifact(tmp_path):
    artifact = tmp_path / "model"
    artifact.mkdir()
    for name in REQUIRED_ARTIFACT_FILES:
        (artifact / name).write_bytes(b"placeholder")
    (artifact / "metadata.json").write_text(
        json.dumps(
            {
                "modelVersion": "cf_test",
                "source": "MOVIELENS",
                "deployable": False,
                "modelTypes": ["user_based", "item_based"],
            }
        ),
        encoding="utf-8",
    )
    (artifact / "metrics.json").write_text(
        json.dumps(
            {
                "runtime": {
                    "models": {
                        "user_based": {"fit_seconds": 0.4},
                        "item_based": {"fit_seconds": 0.5},
                    },
                    "total_fit_seconds": 0.9,
                }
            }
        ),
        encoding="utf-8",
    )
    return artifact


def test_quality_gate_accepts_complete_safe_benchmark(tmp_path) -> None:
    result = run_quality_gate(_complete_artifact(tmp_path))

    assert result.passed
    assert not result.errors


def test_quality_gate_rejects_invalid_runtime(tmp_path) -> None:
    artifact = _complete_artifact(tmp_path)
    (artifact / "metrics.json").write_text(
        json.dumps(
            {
                "runtime": {
                    "models": {
                        "user_based": {"fit_seconds": -1.0},
                        "item_based": {"fit_seconds": 0.5},
                    }
                }
            }
        ),
        encoding="utf-8",
    )

    result = run_quality_gate(artifact)

    assert not result.passed
    assert "runtime.models.user_based.fit_seconds must be non-negative." in result.errors


def test_quality_gate_requires_both_models(tmp_path) -> None:
    artifact = _complete_artifact(tmp_path)
    metadata = json.loads((artifact / "metadata.json").read_text(encoding="utf-8"))
    metadata["modelTypes"] = ["item_based"]
    (artifact / "metadata.json").write_text(json.dumps(metadata), encoding="utf-8")

    result = run_quality_gate(artifact)

    assert not result.passed
    assert "both user_based and item_based" in result.errors[0]
