from __future__ import annotations

from abc import ABC, abstractmethod

import torch
from torch import nn


class RecommendationModel(nn.Module, ABC):
    @abstractmethod
    def preference_logits(
        self,
        user_indices: torch.Tensor,
        item_indices: torch.Tensor,
    ) -> torch.Tensor:
        raise NotImplementedError

    @abstractmethod
    def all_item_preference_logits(self, user_indices: torch.Tensor) -> torch.Tensor:
        raise NotImplementedError
