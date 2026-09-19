from __future__ import annotations

from dataclasses import dataclass
from itertools import combinations
from math import log2, sqrt

import numpy as np
import pandas as pd
import torch

from app.data.mapping import IndexMappings
from app.ranking import (
    blend_preference_with_popularity,
    item_popularity_counts,
    normalized_popularity,
)
from app.recommenders.mbmf import MultiBehaviorMF


@dataclass(slots=True)
class EvaluationResult:
    metrics: dict[str, float | None]
    recommendations: dict[int, list[tuple[int, float]]]


def _seen_by_user(interactions: pd.DataFrame) -> dict[int, set[int]]:
    return {
        int(user): {int(item) for item in items}
        for user, items in interactions.groupby("user_index")["item_index"]
    }


def predict_ratings(
    model: MultiBehaviorMF,
    interactions: pd.DataFrame,
    *,
    device: torch.device,
    batch_size: int = 4096,
) -> np.ndarray:
    predictions: list[np.ndarray] = []
    model.eval()
    with torch.no_grad():
        for start in range(0, len(interactions), batch_size):
            chunk = interactions.iloc[start : start + batch_size]
            users = torch.as_tensor(
                chunk["user_index"].to_numpy(dtype=np.int64),
                dtype=torch.long,
                device=device,
            )
            items = torch.as_tensor(
                chunk["item_index"].to_numpy(dtype=np.int64),
                dtype=torch.long,
                device=device,
            )
            values = model(users, items)["rating"].clamp(1.0, 5.0)
            predictions.append(values.cpu().numpy())
    return np.concatenate(predictions) if predictions else np.asarray([], dtype=np.float32)


def recommend_for_users(
    model: MultiBehaviorMF,
    users: list[int],
    *,
    seen: dict[int, set[int]],
    top_k: int,
    device: torch.device,
    user_batch_size: int = 128,
    popularity: np.ndarray | None = None,
    popularity_weight: float = 0.0,
) -> dict[int, list[tuple[int, float]]]:
    result: dict[int, list[tuple[int, float]]] = {}
    actual_k = min(top_k, model.item_count)
    model.eval()
    with torch.no_grad():
        for start in range(0, len(users), user_batch_size):
            batch_users = users[start : start + user_batch_size]
            tensor_users = torch.as_tensor(batch_users, dtype=torch.long, device=device)
            scores = model.all_item_preference_scores(tensor_users)
            scores = blend_preference_with_popularity(
                scores,
                popularity,
                popularity_weight=popularity_weight,
            )
            for row, user_index in enumerate(batch_users):
                seen_items = seen.get(user_index, set())
                if seen_items:
                    seen_tensor = torch.as_tensor(
                        sorted(seen_items),
                        dtype=torch.long,
                        device=device,
                    )
                    scores[row, seen_tensor] = -torch.inf
                finite_count = int(torch.isfinite(scores[row]).sum().item())
                count = min(actual_k, finite_count)
                if count <= 0:
                    result[user_index] = []
                    continue
                values, indices = torch.topk(scores[row], k=count)
                result[user_index] = [
                    (int(item), float(score))
                    for item, score in zip(
                        indices.cpu().tolist(),
                        values.cpu().tolist(),
                        strict=True,
                    )
                ]
    return result


def _ranking_metrics(
    recommendations: dict[int, list[tuple[int, float]]],
    relevant_by_user: dict[int, set[int]],
    *,
    k: int,
) -> dict[str, float]:
    precisions: list[float] = []
    recalls: list[float] = []
    ndcgs: list[float] = []
    hit_rates: list[float] = []
    for user, relevant in relevant_by_user.items():
        if not relevant:
            continue
        recommended = [item for item, _score in recommendations.get(user, [])[:k]]
        denominator = max(1, min(k, len(recommended)))
        binary = [1 if item in relevant else 0 for item in recommended]
        hits = sum(binary)
        precisions.append(hits / denominator)
        recalls.append(hits / len(relevant))
        dcg = sum(value / log2(rank + 1) for rank, value in enumerate(binary, start=1))
        ideal_count = min(len(relevant), k)
        idcg = sum(1 / log2(rank + 1) for rank in range(1, ideal_count + 1))
        ndcgs.append(dcg / idcg if idcg else 0.0)
        hit_rates.append(float(hits > 0))
    return {
        f"precision@{k}": float(np.mean(precisions)) if precisions else 0.0,
        f"recall@{k}": float(np.mean(recalls)) if recalls else 0.0,
        f"ndcg@{k}": float(np.mean(ndcgs)) if ndcgs else 0.0,
        f"hitrate@{k}": float(np.mean(hit_rates)) if hit_rates else 0.0,
    }


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
    fit_interactions: pd.DataFrame,
    *,
    item_count: int,
    k: int,
) -> float:
    counts = np.ones(item_count, dtype=np.float64)
    for item, count in fit_interactions["item_index"].value_counts().items():
        counts[int(item)] += int(count)
    probabilities = counts / counts.sum()
    values = [
        -log2(probabilities[item])
        for ranked in recommendations.values()
        for item, _score in ranked[:k]
    ]
    return float(np.mean(values)) if values else 0.0


def evaluate_model(
    model: MultiBehaviorMF,
    evaluation_interactions: pd.DataFrame,
    fit_interactions: pd.DataFrame,
    *,
    mappings: IndexMappings,
    items: pd.DataFrame,
    genre_names: list[str],
    k_values: list[int],
    rating_threshold: float,
    device: torch.device,
    popularity_weight: float = 0.0,
) -> EvaluationResult:
    observed_ratings = evaluation_interactions[evaluation_interactions["rating"].notna()]
    predictions = predict_ratings(model, observed_ratings, device=device)
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
        int(user): {int(item) for item in items_for_user}
        for user, items_for_user in relevant_rows.groupby("user_index")["item_index"]
    }
    users = sorted(relevant_by_user)
    maximum_k = max(k_values)
    seen = _seen_by_user(fit_interactions)
    popularity = normalized_popularity(
        item_popularity_counts(
            fit_interactions,
            item_count=len(mappings.item_to_index),
        )
    )
    recommendations = recommend_for_users(
        model,
        users,
        seen=seen,
        top_k=maximum_k,
        device=device,
        popularity=popularity,
        popularity_weight=popularity_weight,
    )
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
    genres = _genre_matrix(items, mappings, genre_names)
    metrics[f"diversity@{maximum_k}"] = _diversity(
        recommendations,
        genres,
        k=maximum_k,
    )
    metrics[f"novelty@{maximum_k}"] = _novelty(
        recommendations,
        fit_interactions,
        item_count=len(mappings.item_to_index),
        k=maximum_k,
    )
    return EvaluationResult(metrics=metrics, recommendations=recommendations)
