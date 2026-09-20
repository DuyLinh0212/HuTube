from __future__ import annotations

from dataclasses import dataclass
from time import perf_counter
from typing import Literal

import pandas as pd

from app.data.mapping import IndexMappings
from app.recommenders.base import CollaborativeFilter
from app.recommenders.item_cf import ItemBasedCF
from app.recommenders.user_cf import UserBasedCF
from training.config import TrainConfig

ModelType = Literal["user_based", "item_based"]
MODEL_TYPES: tuple[ModelType, ModelType] = ("user_based", "item_based")


@dataclass(slots=True)
class FitResult:
    model_type: ModelType
    model: CollaborativeFilter
    fit_seconds: float


def fit_model(
    model_type: ModelType,
    interactions: pd.DataFrame,
    *,
    config: TrainConfig,
    mappings: IndexMappings,
) -> FitResult:
    started = perf_counter()
    model_class = UserBasedCF if model_type == "user_based" else ItemBasedCF
    model = model_class.fit(
        interactions,
        user_count=len(mappings.user_to_index),
        item_count=len(mappings.item_to_index),
        neighbor_count=config.model.neighbor_count,
        interaction_mode=config.model.interaction_mode,
        similarity=config.model.similarity,
    )
    return FitResult(
        model_type=model_type,
        model=model,
        fit_seconds=perf_counter() - started,
    )


def fit_both_models(
    interactions: pd.DataFrame,
    *,
    config: TrainConfig,
    mappings: IndexMappings,
) -> dict[ModelType, FitResult]:
    return {
        model_type: fit_model(
            model_type,
            interactions,
            config=config,
            mappings=mappings,
        )
        for model_type in MODEL_TYPES
    }
