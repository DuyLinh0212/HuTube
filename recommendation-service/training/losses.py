from __future__ import annotations

import torch
import torch.nn.functional as functional

from app.recommenders.mbmf import MultiBehaviorMF


def masked_huber(
    predictions: torch.Tensor,
    targets: torch.Tensor,
    mask: torch.Tensor,
) -> torch.Tensor | None:
    if not bool(mask.any()):
        return None
    return functional.smooth_l1_loss(predictions[mask], targets[mask])


def masked_bce(
    logits: torch.Tensor,
    targets: torch.Tensor,
    mask: torch.Tensor,
) -> torch.Tensor | None:
    if not bool(mask.any()):
        return None
    return functional.binary_cross_entropy_with_logits(logits[mask], targets[mask])


def bpr_loss(
    positive_logits: torch.Tensor,
    negative_logits: torch.Tensor,
) -> torch.Tensor | None:
    if not positive_logits.numel():
        return None
    return -functional.logsigmoid(positive_logits - negative_logits).mean()


def combine_active_losses(
    losses: dict[str, torch.Tensor],
    model: MultiBehaviorMF,
    *,
    weighting: str,
) -> torch.Tensor:
    if not losses:
        raise ValueError("No observed task loss is available for this batch.")
    if weighting == "normalized_equal":
        return torch.stack(list(losses.values())).sum()
    if weighting != "uncertainty":
        raise ValueError(f"Unsupported loss weighting: {weighting}")
    terms = []
    for name, loss in losses.items():
        log_variance = model.task_log_variances[name]
        terms.append(torch.exp(-log_variance) * loss + log_variance)
    return torch.stack(terms).sum()
