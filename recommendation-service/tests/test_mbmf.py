from __future__ import annotations

import torch

from app.ranking import blend_preference_with_popularity, normalized_popularity
from app.recommenders.mbmf import ALL_TASKS, MultiBehaviorMF
from training.losses import combine_active_losses, masked_bce


def test_mbmf_exposes_every_behavior_head() -> None:
    model = MultiBehaviorMF(users=4, items=6, embedding_dimension=8)
    users = torch.tensor([0, 1, 2])
    items = torch.tensor([1, 2, 3])

    outputs = model(users, items)

    assert set(outputs) == set(ALL_TASKS)
    assert all(value.shape == (3,) for value in outputs.values())
    scores = model.all_item_preference_scores(torch.tensor([0, 1]))
    assert scores.shape == (2, 6)
    assert bool(((scores >= 0) & (scores <= 1)).all())


def test_missing_behavior_is_not_added_to_loss() -> None:
    model = MultiBehaviorMF(users=2, items=3, embedding_dimension=4)
    logits = torch.tensor([0.2, -0.1])
    targets = torch.tensor([0.0, 0.0])
    missing_mask = torch.tensor([False, False])

    like_loss = masked_bce(logits, targets, missing_mask)
    total = combine_active_losses(
        {"rating": torch.tensor(1.25, requires_grad=True)},
        model,
        weighting="uncertainty",
    )

    assert like_loss is None
    assert torch.isfinite(total)
    total.backward()
    assert model.task_log_variances["rating"].grad is not None
    assert model.task_log_variances["like"].grad is None


def test_popularity_blend_is_bounded_and_configurable() -> None:
    preference = torch.tensor([[0.2, 0.8]])
    popularity = normalized_popularity(torch.tensor([1.0, 9.0]).numpy())

    blended = blend_preference_with_popularity(
        preference,
        popularity,
        popularity_weight=0.25,
    )

    assert torch.allclose(blended, torch.tensor([[0.15, 0.85]]))
    assert bool(((blended >= 0) & (blended <= 1)).all())
