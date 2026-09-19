from __future__ import annotations

from pathlib import Path
from typing import Literal

import yaml
from pydantic import BaseModel, Field, field_validator


class SplitConfig(BaseModel):
    train: float = 0.80
    validation: float = 0.10
    test: float = 0.10

    @field_validator("test")
    @classmethod
    def validate_total(cls, value: float, info):
        values = info.data
        total = float(values.get("train", 0)) + float(values.get("validation", 0)) + value
        if abs(total - 1.0) > 1e-9:
            raise ValueError("data split ratios must sum to 1.")
        return value


class DataConfig(BaseModel):
    path: Path
    strict_counts: bool = True
    max_users: int | None = Field(default=None, ge=1)
    processed_path: Path
    split: SplitConfig = Field(default_factory=SplitConfig)


class ModelConfig(BaseModel):
    embedding_dimension: int = Field(default=64, ge=2)
    preference_head: bool = True


class TrainingSettings(BaseModel):
    seed: int = 42
    optimizer: Literal["AdamW"] = "AdamW"
    learning_rate: float = Field(default=0.001, gt=0)
    weight_decay: float = Field(default=0.00001, ge=0)
    batch_size: int = Field(default=1024, ge=1)
    max_epochs: int = Field(default=100, ge=1)
    device: Literal["cpu", "cuda"] = "cpu"


class LossConfig(BaseModel):
    rating: Literal["huber"] = "huber"
    like: Literal["bce"] = "bce"
    dislike: Literal["bce"] = "bce"
    comment: Literal["bce"] = "bce"
    share: Literal["bce"] = "bce"
    watch_ratio: Literal["huber"] = "huber"
    preference: Literal["bpr"] = "bpr"
    weighting: Literal["uncertainty", "normalized_equal"] = "uncertainty"


class EarlyStoppingConfig(BaseModel):
    enabled: bool = True
    patience: int = Field(default=8, ge=1)
    metric: Literal["ndcg@10"] = "ndcg@10"
    mode: Literal["max"] = "max"


class NegativeSamplingConfig(BaseModel):
    enabled: bool = True
    negatives_per_positive: int = Field(default=4, ge=1)


class RelevanceConfig(BaseModel):
    rating_threshold: float = Field(default=4.0, ge=1.0, le=5.0)
    watch_ratio_threshold: float = Field(default=0.70, ge=0.0, le=1.0)


class EvaluationConfig(BaseModel):
    k: list[int] = Field(default_factory=lambda: [5, 10, 20])

    @field_validator("k")
    @classmethod
    def validate_k(cls, values: list[int]) -> list[int]:
        normalized = sorted(set(values))
        if not normalized or normalized[0] < 1:
            raise ValueError("evaluation.k must contain positive integers.")
        return normalized


class RankingConfig(BaseModel):
    popularity_weight: float = Field(default=0.0, ge=0.0, le=1.0)


class OutputConfig(BaseModel):
    artifact_root: Path = Path("data/artifacts")
    report_root: Path = Path("reports")


class TrainConfig(BaseModel):
    data: DataConfig
    model: ModelConfig = Field(default_factory=ModelConfig)
    training: TrainingSettings = Field(default_factory=TrainingSettings)
    loss: LossConfig = Field(default_factory=LossConfig)
    early_stopping: EarlyStoppingConfig = Field(default_factory=EarlyStoppingConfig)
    negative_sampling: NegativeSamplingConfig = Field(
        default_factory=NegativeSamplingConfig
    )
    relevance: RelevanceConfig = Field(default_factory=RelevanceConfig)
    evaluation: EvaluationConfig = Field(default_factory=EvaluationConfig)
    ranking: RankingConfig = Field(default_factory=RankingConfig)
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
