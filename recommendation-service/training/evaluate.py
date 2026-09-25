from __future__ import annotations

from dataclasses import dataclass

from app.data.mapping import IndexMappings
from app.recommenders.base import CollaborativeFilter


@dataclass(slots=True)
class EvaluationResult:
    """Technical output for generating recommendations during a smoke run.

    The project does not assign a suitability label to a recommendation. This
    object therefore keeps only the generated lists and their count; it does
    not turn them into an offline quality score.
    """

    metrics: dict[str, float | None]
    recommendations: dict[int, list[tuple[int, float]]]


def recommend_for_users(
    model: CollaborativeFilter,
    users: list[int],
    *,
    top_k: int,
) -> dict[int, list[tuple[int, float]]]:
    return {user: model.recommend(user, limit=top_k) for user in users}


def evaluate_model(
    model: CollaborativeFilter,
    interactions,
    *,
    mappings: IndexMappings,
    items=None,
    genre_names=None,
    k_values: list[int] | None = None,
    positive_rating_threshold: float | None = None,
) -> EvaluationResult:
    """Generate Top-K lists for a technical smoke check.

    The legacy arguments remain accepted so existing callers and old scripts do
    not break. They are intentionally not converted into a recommendation
    quality metric because no user-provided relevance label is available.
    """

    del interactions, items, genre_names, positive_rating_threshold
    maximum_k = max(k_values or [10])
    users = list(range(len(mappings.user_to_index)))
    recommendations = recommend_for_users(model, users, top_k=maximum_k)
    metrics = {
        "recommendation_count": float(
            sum(len(values) for values in recommendations.values())
        )
    }
    return EvaluationResult(metrics=metrics, recommendations=recommendations)
