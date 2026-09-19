from __future__ import annotations

from dataclasses import dataclass

import numpy as np
import pandas as pd
import torch
from torch.utils.data import Dataset

BEHAVIORS = ("rating", "like", "dislike", "comment", "share", "watch_ratio")


class InteractionTensorDataset(Dataset):
    def __init__(self, interactions: pd.DataFrame) -> None:
        self.user_indices = torch.as_tensor(
            interactions["user_index"].to_numpy(dtype=np.int64),
            dtype=torch.long,
        )
        self.item_indices = torch.as_tensor(
            interactions["item_index"].to_numpy(dtype=np.int64),
            dtype=torch.long,
        )
        self.values: dict[str, torch.Tensor] = {}
        self.masks: dict[str, torch.Tensor] = {}
        for behavior in BEHAVIORS:
            observed = interactions[behavior].notna().to_numpy(dtype=np.bool_)
            numeric = pd.to_numeric(interactions[behavior], errors="coerce").fillna(0.0)
            self.values[behavior] = torch.as_tensor(
                numeric.to_numpy(dtype=np.float32),
                dtype=torch.float32,
            )
            self.masks[behavior] = torch.as_tensor(observed, dtype=torch.bool)

    def __len__(self) -> int:
        return len(self.user_indices)

    def __getitem__(self, index: int) -> dict[str, torch.Tensor]:
        return {
            "user_index": self.user_indices[index],
            "item_index": self.item_indices[index],
            **{behavior: self.values[behavior][index] for behavior in BEHAVIORS},
            **{f"{behavior}_mask": self.masks[behavior][index] for behavior in BEHAVIORS},
        }


@dataclass(slots=True)
class NegativeSampler:
    candidates_by_user: list[np.ndarray]
    rng: np.random.Generator

    @classmethod
    def from_interactions(
        cls,
        interactions: pd.DataFrame,
        *,
        user_count: int,
        item_count: int,
        rating_threshold: float,
        seed: int,
    ) -> NegativeSampler:
        relevant = interactions[
            interactions["rating"].notna() & (interactions["rating"] >= rating_threshold)
        ]
        positive_by_user = {
            int(user): set(int(value) for value in items)
            for user, items in relevant.groupby("user_index")["item_index"]
        }
        catalog = np.arange(item_count, dtype=np.int64)
        candidates: list[np.ndarray] = []
        for user_index in range(user_count):
            positives = positive_by_user.get(user_index, set())
            if not positives:
                candidates.append(catalog)
                continue
            mask = np.ones(item_count, dtype=bool)
            mask[list(positives)] = False
            candidates.append(catalog[mask])
        return cls(candidates_by_user=candidates, rng=np.random.default_rng(seed))

    def sample(
        self,
        user_indices: torch.Tensor,
        negatives_per_positive: int,
        *,
        device: torch.device,
    ) -> tuple[torch.Tensor, torch.Tensor]:
        repeated_users: list[int] = []
        sampled_items: list[int] = []
        for user_index in user_indices.detach().cpu().tolist():
            candidates = self.candidates_by_user[int(user_index)]
            if not len(candidates):
                continue
            chosen = self.rng.choice(
                candidates,
                size=negatives_per_positive,
                replace=len(candidates) < negatives_per_positive,
            )
            repeated_users.extend([int(user_index)] * negatives_per_positive)
            sampled_items.extend(int(value) for value in chosen)
        return (
            torch.as_tensor(repeated_users, dtype=torch.long, device=device),
            torch.as_tensor(sampled_items, dtype=torch.long, device=device),
        )
