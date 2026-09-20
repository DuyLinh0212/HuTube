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

ModelFamily = Literal["user_based", "item_based"]
ModelType = str
MODEL_FAMILIES: tuple[ModelFamily, ModelFamily] = ("user_based", "item_based")
# Legacy names remain valid aliases for the cosine variant used by the API.
MODEL_TYPES: tuple[ModelFamily, ModelFamily] = MODEL_FAMILIES
SIMILARITY_NAMES = ("cosine", "jaccard", "pearson")


def configured_model_types(config: TrainConfig) -> tuple[str, ...]:
    return tuple(
        variant_name(family, similarity)
        for family in MODEL_FAMILIES
        for similarity in config.model.selected_similarities
    )


@dataclass(slots=True)
class FitResult:
    model_type: str
    model: CollaborativeFilter
    fit_seconds: float


def variant_name(family: ModelFamily, similarity: str) -> str:
    if similarity not in SIMILARITY_NAMES:
        raise ValueError(f"Unsupported similarity: {similarity}")
    return f"{family}_{similarity}"


def split_variant(model_type: str) -> tuple[ModelFamily, str]:
    if model_type in MODEL_FAMILIES:
        return model_type, "cosine"  # compatibility alias
    try:
        family, similarity = model_type.rsplit("_", 1)
    except ValueError as exc:
        raise ValueError(f"Unsupported model type: {model_type}") from exc
    if family not in MODEL_FAMILIES or similarity not in SIMILARITY_NAMES:
        raise ValueError(f"Unsupported model type: {model_type}")
    return family, similarity  # type: ignore[return-value]


def fit_model(
    model_type: str,
    interactions: pd.DataFrame,
    *,
    config: TrainConfig,
    mappings: IndexMappings,
) -> FitResult:
    started = perf_counter()
    family, similarity = split_variant(model_type)
    model_class = UserBasedCF if family == "user_based" else ItemBasedCF
    model = model_class.fit(
        interactions,
        user_count=len(mappings.user_to_index),
        item_count=len(mappings.item_to_index),
        neighbor_count=config.model.neighbor_count,
        interaction_mode=config.model.interaction_mode,
        similarity=similarity,  # type: ignore[arg-type]
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
    """Compatibility helper that fits one cosine model per family."""
    return {
        model_type: fit_model(
            model_type,
            interactions,
            config=config,
            mappings=mappings,
        )
        for model_type in MODEL_TYPES
    }


def fit_all_models(
    interactions: pd.DataFrame,
    *,
    config: TrainConfig,
    mappings: IndexMappings,
) -> dict[str, FitResult]:
    """Fit every configured User-Based and Item-Based similarity variant."""
    return {
        variant_name(family, similarity): fit_model(
            variant_name(family, similarity),
            interactions,
            config=config,
            mappings=mappings,
        )
        for family in MODEL_FAMILIES
        for similarity in config.model.selected_similarities
    }
