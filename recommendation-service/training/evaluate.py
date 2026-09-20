from __future__ import annotations

from dataclasses import dataclass
from itertools import combinations
from math import log2

import numpy as np
import pandas as pd

from app.data.mapping import IndexMappings
from app.recommenders.base import CollaborativeFilter


@dataclass(slots=True)
class EvaluationResult:
    metrics: dict[str, float | None]
    recommendations: dict[int, list[tuple[int, float]]]


def _genre_matrix(
    items: pd.DataFrame,
    mappings: IndexMappings,
    genre_names: list[str],
) -> np.ndarray:
    matrix = np.zeros((len(mappings.item_to_index), len(genre_names)), dtype=np.float32)
    for _row_index, row in items.iterrows():
        item_index = mappings.item_to_index.get(str(row["item_id"]))
        if item_index is None:
            continue
        for genre_index, genre in enumerate(genre_names):
            matrix[item_index, genre_index] = float(row[genre])
    return matrix


def build_user_preference_profiles(
    interactions: pd.DataFrame,
    *,
    mappings: IndexMappings,
    items: pd.DataFrame,
    genre_names: list[str],
    positive_rating_threshold: float,
) -> np.ndarray:
    """Build preference profiles from the user's complete observed history.

    This is evaluation-only metadata. Neither CF model receives genre columns while
    fitting or ranking. A profile is a normalized genre distribution assembled from
    high-rated history; users without a high-rated row fall back to all rated history.
    """
    genres = _genre_matrix(items, mappings, genre_names)
    profiles = np.zeros((len(mappings.user_to_index), len(genre_names)), dtype=np.float32)
    observed = interactions[interactions["rating"].notna()]
    for user_index, group in observed.groupby("user_index"):
        positive = group[group["rating"] >= positive_rating_threshold]
        selected = positive if not positive.empty else group
        item_indices = selected["item_index"].to_numpy(dtype=np.int64)
        weights = selected["rating"].to_numpy(dtype=np.float32) / 5.0
        profiles[int(user_index)] = (genres[item_indices] * weights[:, None]).sum(axis=0)

    totals = profiles.sum(axis=1, keepdims=True)
    np.divide(profiles, totals, out=profiles, where=totals > 0)
    return profiles


def _preference_alignment(
    recommendations: dict[int, list[tuple[int, float]]],
    profiles: np.ndarray,
    genres: np.ndarray,
    *,
    k: int,
) -> float:
    """Measure how much of a user's preferred genre profile each item covers."""
    values: list[float] = []
    for user_index, ranked in recommendations.items():
        if not ranked:
            continue
        profile = profiles[user_index]
        item_values = [float(profile @ genres[item]) for item, _score in ranked[:k]]
        if item_values:
            values.append(float(np.mean(item_values)))
    return float(np.mean(values)) if values else 0.0


def _preference_genre_coverage(
    recommendations: dict[int, list[tuple[int, float]]],
    profiles: np.ndarray,
    genres: np.ndarray,
    *,
    k: int,
) -> float:
    """Measure how many preferred genres appear anywhere in the Top-K list."""
    values: list[float] = []
    for user_index, ranked in recommendations.items():
        preferred = set(np.flatnonzero(profiles[user_index] > 0))
        if not preferred:
            continue
        recommended = set(
            int(genre_index)
            for item, _score in ranked[:k]
            for genre_index in np.flatnonzero(genres[item] > 0)
        )
        values.append(len(preferred & recommended) / len(preferred))
    return float(np.mean(values)) if values else 0.0


def _diversity(
    recommendations: dict[int, list[tuple[int, float]]],
    genres: np.ndarray,
    *,
    k: int,
) -> float:
    values: list[float] = []
    for ranked in recommendations.values():
        item_ids = [item for item, _score in ranked[:k]]
        if len(item_ids) < 2:
            continue
        similarities: list[float] = []
        for left, right in combinations(item_ids, 2):
            a = genres[left] > 0
            b = genres[right] > 0
            union = int(np.logical_or(a, b).sum())
            similarity = float(np.logical_and(a, b).sum() / union) if union else 0.0
            similarities.append(similarity)
        values.append(1.0 - float(np.mean(similarities)))
    return float(np.mean(values)) if values else 0.0


def _novelty(
    recommendations: dict[int, list[tuple[int, float]]],
    interactions: pd.DataFrame,
    *,
    item_count: int,
    k: int,
) -> float:
    counts = np.ones(item_count, dtype=np.float64)
    for item, count in interactions["item_index"].value_counts().items():
        counts[int(item)] += int(count)
    probabilities = counts / counts.sum()
    values = [
        -log2(probabilities[item])
        for ranked in recommendations.values()
        for item, _score in ranked[:k]
    ]
    return float(np.mean(values)) if values else 0.0


def recommend_for_users(
    model: CollaborativeFilter,
    users: list[int],
    *,
    top_k: int,
) -> dict[int, list[tuple[int, float]]]:
    return {
        user: model.recommend(user, limit=top_k)
        for user in users
    }


def evaluate_model(
    model: CollaborativeFilter,
    interactions: pd.DataFrame,
    *,
    mappings: IndexMappings,
    items: pd.DataFrame,
    genre_names: list[str],
    k_values: list[int],
    positive_rating_threshold: float,
) -> EvaluationResult:
    """Evaluate preference fit without hiding or matching an exact item ID.

    Every user's complete observed history is used to construct a genre preference
    profile. The model recommends unseen items, and metrics measure preference
    alignment, preferred-genre coverage, catalog coverage, diversity and novelty.
    Genre metadata is used only for this offline evaluation, never by the CF scorer.
    """
    maximum_k = max(k_values)
    users = list(range(len(mappings.user_to_index)))
    recommendations = recommend_for_users(model, users, top_k=maximum_k)
    genres = _genre_matrix(items, mappings, genre_names)
    profiles = build_user_preference_profiles(
        interactions,
        mappings=mappings,
        items=items,
        genre_names=genre_names,
        positive_rating_threshold=positive_rating_threshold,
    )

    metrics: dict[str, float | None] = {}
    for k in k_values:
        metrics[f"preference_alignment@{k}"] = _preference_alignment(
            recommendations,
            profiles,
            genres,
            k=k,
        )
        metrics[f"preference_genre_coverage@{k}"] = _preference_genre_coverage(
            recommendations,
            profiles,
            genres,
            k=k,
        )

    covered = {
        item
        for ranked in recommendations.values()
        for item, _score in ranked[:maximum_k]
    }
    metrics[f"catalog_coverage@{maximum_k}"] = (
        len(covered) / len(mappings.item_to_index) if mappings.item_to_index else 0.0
    )
    metrics[f"diversity@{maximum_k}"] = _diversity(
        recommendations,
        genres,
        k=maximum_k,
    )
    metrics[f"novelty@{maximum_k}"] = _novelty(
        recommendations,
        interactions,
        item_count=len(mappings.item_to_index),
        k=maximum_k,
    )
    metrics["recommendation_count"] = float(
        sum(len(values) for values in recommendations.values())
    )
    return EvaluationResult(metrics=metrics, recommendations=recommendations)
