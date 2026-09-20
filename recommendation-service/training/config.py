from __future__ import annotations

from pathlib import Path
from typing import Literal

import yaml
from pydantic import BaseModel, Field, field_validator


class DataConfig(BaseModel):
    path: Path
    strict_counts: bool = True
    max_users: int | None = Field(default=None, ge=1)
    processed_path: Path


class ModelConfig(BaseModel):
    """Parameters shared by User-Based and Item-Based CF."""

    similarity: Literal["cosine", "jaccard"] = "cosine"
    interaction_mode: Literal["binary", "rating"] = "rating"
    neighbor_count: int = Field(default=50, ge=1)


class PreferenceConfig(BaseModel):
    positive_rating_threshold: float = Field(default=4.0, ge=1.0, le=5.0)


class EvaluationConfig(BaseModel):
    k: list[int] = Field(default_factory=lambda: [5, 10, 20])

    @field_validator("k")
    @classmethod
    def validate_k(cls, values: list[int]) -> list[int]:
        normalized = sorted(set(values))
        if not normalized or normalized[0] < 1:
            raise ValueError("evaluation.k must contain positive integers.")
        return normalized


class OutputConfig(BaseModel):
    artifact_root: Path = Path("data/artifacts")
    report_root: Path = Path("reports")


class TrainConfig(BaseModel):
    data: DataConfig
    model: ModelConfig = Field(default_factory=ModelConfig)
    preference: PreferenceConfig = Field(default_factory=PreferenceConfig)
    evaluation: EvaluationConfig = Field(default_factory=EvaluationConfig)
    output: OutputConfig = Field(default_factory=OutputConfig)

    project_root: Path = Field(exclude=True)

    def resolve(self, path: Path) -> Path:
        return path if path.is_absolute() else (self.project_root / path).resolve()


def load_train_config(path: str | Path) -> TrainConfig:
    config_path = Path(path).expanduser().resolve()
    payload = yaml.safe_load(config_path.read_text(encoding="utf-8"))
    if not isinstance(payload, dict):
        raise ValueError(f"Training config must be a YAML object: {config_path}")
    project_root = config_path.parent.parent
    return TrainConfig.model_validate({**payload, "project_root": project_root})
