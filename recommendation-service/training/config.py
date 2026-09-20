from __future__ import annotations

from pathlib import Path
from typing import Literal

import yaml
from pydantic import BaseModel, Field, field_validator

from app.recommenders.similarity import SimilarityName


class DataConfig(BaseModel):
    path: Path
    strict_counts: bool = True
    max_users: int | None = Field(default=None, ge=1)
    processed_path: Path


class ModelConfig(BaseModel):
    """Parameters shared by all from-scratch CF variants."""

    similarities: list[SimilarityName] = Field(
        default_factory=lambda: ["cosine", "jaccard", "pearson"]
    )
    # Kept for old local configs.  New configs should use ``similarities``.
    similarity: SimilarityName | None = None
    interaction_mode: Literal["binary", "rating"] = "rating"
    neighbor_count: int = Field(default=50, ge=1)

    @field_validator("similarities")
    @classmethod
    def validate_similarities(cls, values: list[SimilarityName]) -> list[SimilarityName]:
        normalized = list(dict.fromkeys(values))
        if not normalized:
            raise ValueError("model.similarities must contain at least one metric.")
        return normalized

    @property
    def selected_similarities(self) -> list[SimilarityName]:
        """Return configured metrics, honoring the legacy singular field."""
        return [self.similarity] if self.similarity is not None else list(self.similarities)


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


class BenchmarkConfig(BaseModel):
    enabled: bool = True
    similarity: SimilarityName = "cosine"


class OutputConfig(BaseModel):
    artifact_root: Path = Path("data/artifacts")
    report_root: Path = Path("reports")


class TrainConfig(BaseModel):
    data: DataConfig
    model: ModelConfig = Field(default_factory=ModelConfig)
    preference: PreferenceConfig = Field(default_factory=PreferenceConfig)
    evaluation: EvaluationConfig = Field(default_factory=EvaluationConfig)
    benchmark: BenchmarkConfig = Field(default_factory=BenchmarkConfig)
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
