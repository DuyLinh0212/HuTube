from __future__ import annotations

import copy
import random
from dataclasses import dataclass

import numpy as np
import pandas as pd
import torch
from torch.utils.data import DataLoader

from app.data.mapping import IndexMappings
from app.recommenders.mbmf import MultiBehaviorMF
from training.config import TrainConfig
from training.datasets import InteractionTensorDataset, NegativeSampler
from training.evaluate import evaluate_model
from training.losses import bpr_loss, combine_active_losses, masked_bce, masked_huber

BINARY_BEHAVIORS = ("like", "dislike", "comment", "share")


@dataclass(slots=True)
class TrainingResult:
    model: MultiBehaviorMF
    best_epoch: int
    history: list[dict[str, float | int]]
    active_tasks: list[str]


def seed_everything(seed: int) -> None:
    random.seed(seed)
    np.random.seed(seed)
    torch.manual_seed(seed)
    if torch.cuda.is_available():
        torch.cuda.manual_seed_all(seed)
    torch.use_deterministic_algorithms(True, warn_only=True)


def resolve_device(config: TrainConfig) -> torch.device:
    requested = config.training.device
    if requested == "cuda" and not torch.cuda.is_available():
        raise RuntimeError("training.device=cuda but CUDA is not available.")
    return torch.device(requested)


def create_model(
    config: TrainConfig,
    *,
    user_count: int,
    item_count: int,
    rating_mean: float,
    device: torch.device,
) -> MultiBehaviorMF:
    model = MultiBehaviorMF(
        users=user_count,
        items=item_count,
        embedding_dimension=config.model.embedding_dimension,
    )
    model.set_rating_bias(rating_mean)
    return model.to(device)


def _positive_mask(batch: dict[str, torch.Tensor], config: TrainConfig) -> torch.Tensor:
    result = batch["rating_mask"] & (batch["rating"] >= config.relevance.rating_threshold)
    result = result | (batch["like_mask"] & (batch["like"] >= 0.5))
    result = result | (batch["share_mask"] & (batch["share"] >= 0.5))
    result = result | (
        batch["watch_ratio_mask"]
        & (batch["watch_ratio"] >= config.relevance.watch_ratio_threshold)
    )
    return result


def _move_batch(
    batch: dict[str, torch.Tensor],
    device: torch.device,
) -> dict[str, torch.Tensor]:
    return {name: value.to(device) for name, value in batch.items()}


def _train_epochs(
    model: MultiBehaviorMF,
    fit_interactions: pd.DataFrame,
    *,
    validation_interactions: pd.DataFrame | None,
    config: TrainConfig,
    mappings: IndexMappings,
    items: pd.DataFrame,
    genre_names: list[str],
    epochs: int,
    enable_early_stopping: bool,
    restore_best: bool,
    device: torch.device,
) -> tuple[int, list[dict[str, float | int]], list[str]]:
    generator = torch.Generator()
    generator.manual_seed(config.training.seed)
    loader = DataLoader(
        InteractionTensorDataset(fit_interactions),
        batch_size=config.training.batch_size,
        shuffle=True,
        generator=generator,
    )
    sampler = NegativeSampler.from_interactions(
        fit_interactions,
        user_count=len(mappings.user_to_index),
        item_count=len(mappings.item_to_index),
        rating_threshold=config.relevance.rating_threshold,
        seed=config.training.seed,
    )
    optimizer = torch.optim.AdamW(
        model.parameters(),
        lr=config.training.learning_rate,
        weight_decay=config.training.weight_decay,
    )
    best_metric = -float("inf")
    best_epoch = 1
    best_state = copy.deepcopy(model.state_dict())
    stale = 0
    history: list[dict[str, float | int]] = []
    observed_tasks: set[str] = set()

    for epoch in range(1, epochs + 1):
        model.train()
        total_loss = 0.0
        batches = 0
        for raw_batch in loader:
            batch = _move_batch(raw_batch, device)
            outputs = model(batch["user_index"], batch["item_index"])
            losses: dict[str, torch.Tensor] = {}
            rating_loss = masked_huber(
                outputs["rating"],
                batch["rating"],
                batch["rating_mask"],
            )
            if rating_loss is not None:
                losses["rating"] = rating_loss
            for behavior in BINARY_BEHAVIORS:
                value = masked_bce(
                    outputs[behavior],
                    batch[behavior],
                    batch[f"{behavior}_mask"],
                )
                if value is not None:
                    losses[behavior] = value
            watch_loss = masked_huber(
                torch.sigmoid(outputs["watch_ratio"]),
                batch["watch_ratio"],
                batch["watch_ratio_mask"],
            )
            if watch_loss is not None:
                losses["watch_ratio"] = watch_loss

            positives = _positive_mask(batch, config)
            if config.negative_sampling.enabled and bool(positives.any()):
                positive_users = batch["user_index"][positives]
                positive_items = batch["item_index"][positives]
                negative_users, negative_items = sampler.sample(
                    positive_users,
                    config.negative_sampling.negatives_per_positive,
                    device=device,
                )
                if negative_users.numel():
                    repeated_positive_items = positive_items.repeat_interleave(
                        config.negative_sampling.negatives_per_positive
                    )[: negative_users.numel()]
                    positive_logits = model.preference_logits(
                        negative_users,
                        repeated_positive_items,
                    )
                    negative_logits = model.preference_logits(
                        negative_users,
                        negative_items,
                    )
                    preference_loss = bpr_loss(positive_logits, negative_logits)
                    if preference_loss is not None:
                        losses["preference"] = preference_loss

            if not losses:
                continue
            observed_tasks.update(losses)
            loss = combine_active_losses(
                losses,
                model,
                weighting=config.loss.weighting,
            )
            optimizer.zero_grad(set_to_none=True)
            loss.backward()
            optimizer.step()
            total_loss += float(loss.detach().cpu())
            batches += 1

        row: dict[str, float | int] = {
            "epoch": epoch,
            "train_loss": total_loss / max(1, batches),
        }
        monitored = -row["train_loss"]
        if validation_interactions is not None and len(validation_interactions):
            observed_validation = validation_interactions[
                validation_interactions["rating"].notna()
            ]
            predictions = model(
                torch.as_tensor(
                    observed_validation["user_index"].to_numpy(dtype=np.int64),
                    dtype=torch.long,
                    device=device,
                ),
                torch.as_tensor(
                    observed_validation["item_index"].to_numpy(dtype=np.int64),
                    dtype=torch.long,
                    device=device,
                ),
            )["rating"].clamp(1.0, 5.0)
            targets = torch.as_tensor(
                observed_validation["rating"].to_numpy(dtype=np.float32),
                dtype=torch.float32,
                device=device,
            )
            validation_loss = torch.nn.functional.smooth_l1_loss(predictions, targets)
            row["validation_loss"] = float(validation_loss.detach().cpu())
            validation_result = evaluate_model(
                model,
                validation_interactions,
                fit_interactions,
                mappings=mappings,
                items=items,
                genre_names=genre_names,
                k_values=config.evaluation.k,
                rating_threshold=config.relevance.rating_threshold,
                device=device,
                popularity_weight=config.ranking.popularity_weight,
            )
            monitored = float(validation_result.metrics.get("ndcg@10") or 0.0)
            row["validation_ndcg@10"] = monitored
        history.append(row)

        if monitored > best_metric + 1e-8:
            best_metric = monitored
            best_epoch = epoch
            best_state = copy.deepcopy(model.state_dict())
            stale = 0
        else:
            stale += 1
            if enable_early_stopping and stale >= config.early_stopping.patience:
                break

    if restore_best:
        model.load_state_dict(best_state)
    return best_epoch, history, sorted(observed_tasks)


def train_with_validation(
    train_interactions: pd.DataFrame,
    validation_interactions: pd.DataFrame,
    *,
    config: TrainConfig,
    mappings: IndexMappings,
    items: pd.DataFrame,
    genre_names: list[str],
) -> TrainingResult:
    seed_everything(config.training.seed)
    device = resolve_device(config)
    model = create_model(
        config,
        user_count=len(mappings.user_to_index),
        item_count=len(mappings.item_to_index),
        rating_mean=float(train_interactions["rating"].mean()),
        device=device,
    )
    best_epoch, history, active_tasks = _train_epochs(
        model,
        train_interactions,
        validation_interactions=validation_interactions,
        config=config,
        mappings=mappings,
        items=items,
        genre_names=genre_names,
        epochs=config.training.max_epochs,
        enable_early_stopping=config.early_stopping.enabled,
        restore_best=True,
        device=device,
    )
    return TrainingResult(
        model=model,
        best_epoch=best_epoch,
        history=history,
        active_tasks=active_tasks,
    )


def fit_final_model(
    fit_interactions: pd.DataFrame,
    *,
    config: TrainConfig,
    mappings: IndexMappings,
    items: pd.DataFrame,
    genre_names: list[str],
    epochs: int,
) -> TrainingResult:
    seed_everything(config.training.seed)
    device = resolve_device(config)
    model = create_model(
        config,
        user_count=len(mappings.user_to_index),
        item_count=len(mappings.item_to_index),
        rating_mean=float(fit_interactions["rating"].mean()),
        device=device,
    )
    _best_epoch, history, active_tasks = _train_epochs(
        model,
        fit_interactions,
        validation_interactions=None,
        config=config,
        mappings=mappings,
        items=items,
        genre_names=genre_names,
        epochs=max(1, epochs),
        enable_early_stopping=False,
        restore_best=False,
        device=device,
    )
    return TrainingResult(
        model=model,
        best_epoch=max(1, epochs),
        history=history,
        active_tasks=active_tasks,
    )
