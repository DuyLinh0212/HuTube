from __future__ import annotations

from math import sqrt

import numpy as np
import pandas as pd

from app.data.mapping import IndexMappings
from app.recommenders.item_cf import ItemBasedCF
from training.evaluate import (
    EvaluationResult,
    _diversity,
    _genre_matrix,
    _novelty,
    _ranking_metrics,
)


def evaluate_item_cf(
    model: ItemBasedCF,
    evaluation_interactions: pd.DataFrame,
    fit_interactions: pd.DataFrame,
    *,
    mappings: IndexMappings,
    items: pd.DataFrame,
    genre_names: list[str],
    k_values: list[int],
    rating_threshold: float,
) -> EvaluationResult:
    observed_ratings = evaluation_interactions[
        evaluation_interactions["rating"].notna()
    ]
    predictions = model.predict_pairs(
        observed_ratings["user_index"].to_numpy(dtype=np.int64),
        observed_ratings["item_index"].to_numpy(dtype=np.int64),
    )
    targets = observed_ratings["rating"].to_numpy(dtype=np.float32)
    errors = predictions - targets
    metrics: dict[str, float | None] = {
        "rmse": sqrt(float(np.mean(np.square(errors)))) if len(errors) else None,
        "mae": float(np.mean(np.abs(errors))) if len(errors) else None,
    }

    relevant_rows = evaluation_interactions[
        evaluation_interactions["rating"].notna()
        & (evaluation_interactions["rating"] >= rating_threshold)
    ]
    relevant_by_user = {
        int(user): {int(item) for item in item_ids}
        for user, item_ids in relevant_rows.groupby("user_index")["item_index"]
    }
    maximum_k = max(k_values)
    recommendations = {
        user_index: model.recommend(user_index, limit=maximum_k)
        for user_index in sorted(relevant_by_user)
    }
    for k in k_values:
        metrics.update(_ranking_metrics(recommendations, relevant_by_user, k=k))

    covered = {
        item
        for ranked in recommendations.values()
        for item, _score in ranked[:maximum_k]
    }
    metrics[f"catalog_coverage@{maximum_k}"] = (
        len(covered) / len(mappings.item_to_index) if mappings.item_to_index else 0.0
    )
    genre_matrix = _genre_matrix(items, mappings, genre_names)
    metrics[f"diversity@{maximum_k}"] = _diversity(
        recommendations,
        genre_matrix,
        k=maximum_k,
    )
    metrics[f"novelty@{maximum_k}"] = _novelty(
        recommendations,
        fit_interactions,
        item_count=len(mappings.item_to_index),
        k=maximum_k,
    )
    return EvaluationResult(metrics=metrics, recommendations=recommendations)
