from __future__ import annotations

from typing import Literal

import numpy as np
import pandas as pd

SimilarityName = Literal["cosine", "jaccard"]
InteractionMode = Literal["binary", "rating"]


def build_interaction_matrix(
    interactions: pd.DataFrame,
    *,
    user_count: int,
    item_count: int,
    mode: InteractionMode,
) -> np.ndarray:
    """Build X[user, item] using only collaborative interaction data."""
    if mode not in {"binary", "rating"}:
        raise ValueError("mode must be 'binary' or 'rating'.")
    required = {"user_index", "item_index", "rating"}
    missing = required.difference(interactions.columns)
    if missing:
        raise ValueError(f"Missing interaction columns: {', '.join(sorted(missing))}")

    observed = interactions[interactions["rating"].notna()]
    matrix = np.zeros((user_count, item_count), dtype=np.float32)
    if observed.empty:
        return matrix

    users = observed["user_index"].to_numpy(dtype=np.int64)
    items = observed["item_index"].to_numpy(dtype=np.int64)
    if (
        (users < 0).any()
        or (users >= user_count).any()
        or (items < 0).any()
        or (items >= item_count).any()
    ):
        raise ValueError("Interaction index is outside the configured matrix shape.")

    if mode == "binary":
        matrix[users, items] = 1.0
        return matrix

    values = observed["rating"].to_numpy(dtype=np.float32)
    totals = np.zeros_like(matrix)
    counts = np.zeros_like(matrix)
    np.add.at(totals, (users, items), values)
    np.add.at(counts, (users, items), 1.0)
    np.divide(totals, counts, out=matrix, where=counts > 0)
    return matrix


def cosine_similarity(matrix: np.ndarray) -> np.ndarray:
    """Compute pairwise cosine similarity without a recommender library."""
    values = np.asarray(matrix, dtype=np.float32)
    norms = np.linalg.norm(values, axis=1)
    denominator = norms[:, None] * norms[None, :]
    similarity = np.zeros((values.shape[0], values.shape[0]), dtype=np.float32)
    np.divide(values @ values.T, denominator, out=similarity, where=denominator > 0)
    np.fill_diagonal(similarity, 0.0)
    return np.clip(similarity, 0.0, 1.0)


def jaccard_similarity(matrix: np.ndarray) -> np.ndarray:
    """Compute pairwise Jaccard similarity for implicit interaction vectors."""
    binary = np.asarray(matrix > 0, dtype=np.float32)
    intersection = binary @ binary.T
    cardinality = binary.sum(axis=1)
    union = cardinality[:, None] + cardinality[None, :] - intersection
    similarity = np.zeros_like(intersection, dtype=np.float32)
    np.divide(intersection, union, out=similarity, where=union > 0)
    np.fill_diagonal(similarity, 0.0)
    return similarity


def compute_similarity(matrix: np.ndarray, name: SimilarityName) -> np.ndarray:
    if name == "cosine":
        return cosine_similarity(matrix)
    if name == "jaccard":
        return jaccard_similarity(matrix)
    raise ValueError(f"Unsupported similarity: {name}")


def select_positive_neighbors(
    similarity: np.ndarray,
    neighbor_count: int,
) -> tuple[np.ndarray, np.ndarray]:
    """Keep the strongest positive neighbors with deterministic tie breaking."""
    if neighbor_count < 1:
        raise ValueError("neighbor_count must be positive.")
    count = similarity.shape[0]
    effective = min(neighbor_count, max(0, count - 1))
    indices = np.full((count, effective), -1, dtype=np.int64)
    values = np.zeros((count, effective), dtype=np.float32)
    if effective == 0:
        return indices, values

    for row in range(count):
        candidates = np.flatnonzero(similarity[row] > 0.0)
        candidates = candidates[candidates != row]
        ordered = sorted(
            (int(candidate) for candidate in candidates),
            key=lambda candidate: (-float(similarity[row, candidate]), candidate),
        )[:effective]
        if ordered:
            selected = np.asarray(ordered, dtype=np.int64)
            indices[row, : len(selected)] = selected
            values[row, : len(selected)] = similarity[row, selected]
    return indices, values


def item_means(interaction_matrix: np.ndarray) -> np.ndarray:
    observed = interaction_matrix > 0
    totals = interaction_matrix.sum(axis=0)
    counts = observed.sum(axis=0)
    means = np.zeros(interaction_matrix.shape[1], dtype=np.float32)
    np.divide(totals, counts, out=means, where=counts > 0)
    return means


def rank_scores(
    scores: np.ndarray,
    *,
    limit: int,
    excluded: set[int] | None = None,
) -> list[tuple[int, float]]:
    if limit < 1:
        raise ValueError("limit must be positive.")
    ranked_scores = np.asarray(scores, dtype=np.float32).copy()
    for index in excluded or set():
        if 0 <= int(index) < len(ranked_scores):
            ranked_scores[int(index)] = -np.inf
    candidates = [int(index) for index in np.flatnonzero(np.isfinite(ranked_scores))]
    candidates.sort(key=lambda index: (-float(ranked_scores[index]), index))
    return [
        (index, float(ranked_scores[index]))
        for index in candidates[: min(limit, len(candidates))]
    ]
