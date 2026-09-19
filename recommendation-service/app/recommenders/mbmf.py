from __future__ import annotations

import torch
from torch import nn

from .base import RecommendationModel

BEHAVIOR_HEADS = ("rating", "like", "dislike", "comment", "share", "watch_ratio")
ALL_TASKS = (*BEHAVIOR_HEADS, "preference")


class BehaviorHead(nn.Module):
    def __init__(self, users: int, items: int, embedding_dimension: int) -> None:
        super().__init__()
        self.latent_weight = nn.Parameter(torch.ones(embedding_dimension))
        self.user_bias = nn.Embedding(users, 1)
        self.item_bias = nn.Embedding(items, 1)
        self.global_bias = nn.Parameter(torch.zeros(()))
        nn.init.zeros_(self.user_bias.weight)
        nn.init.zeros_(self.item_bias.weight)

    def pair_logits(
        self,
        user_indices: torch.Tensor,
        item_indices: torch.Tensor,
        user_vectors: torch.Tensor,
        item_vectors: torch.Tensor,
    ) -> torch.Tensor:
        interaction = (user_vectors * item_vectors * self.latent_weight).sum(dim=-1)
        return (
            interaction
            + self.user_bias(user_indices).squeeze(-1)
            + self.item_bias(item_indices).squeeze(-1)
            + self.global_bias
        )

    def all_item_logits(
        self,
        user_indices: torch.Tensor,
        user_vectors: torch.Tensor,
        all_item_vectors: torch.Tensor,
    ) -> torch.Tensor:
        interaction = (user_vectors * self.latent_weight) @ all_item_vectors.T
        return (
            interaction
            + self.user_bias(user_indices)
            + self.item_bias.weight.squeeze(-1).unsqueeze(0)
            + self.global_bias
        )


class MultiBehaviorMF(RecommendationModel):
    def __init__(
        self,
        users: int,
        items: int,
        embedding_dimension: int = 64,
    ) -> None:
        super().__init__()
        self.user_embedding = nn.Embedding(users, embedding_dimension)
        self.item_embedding = nn.Embedding(items, embedding_dimension)
        self.heads = nn.ModuleDict(
            {
                name: BehaviorHead(users, items, embedding_dimension)
                for name in ALL_TASKS
            }
        )
        self.task_log_variances = nn.ParameterDict(
            {name: nn.Parameter(torch.zeros(())) for name in ALL_TASKS}
        )
        nn.init.normal_(self.user_embedding.weight, mean=0.0, std=0.05)
        nn.init.normal_(self.item_embedding.weight, mean=0.0, std=0.05)

    @property
    def user_count(self) -> int:
        return self.user_embedding.num_embeddings

    @property
    def item_count(self) -> int:
        return self.item_embedding.num_embeddings

    @property
    def embedding_dimension(self) -> int:
        return self.user_embedding.embedding_dim

    def set_rating_bias(self, rating_mean: float) -> None:
        with torch.no_grad():
            self.heads["rating"].global_bias.fill_(float(rating_mean))

    def forward(
        self,
        user_indices: torch.Tensor,
        item_indices: torch.Tensor,
    ) -> dict[str, torch.Tensor]:
        user_vectors = self.user_embedding(user_indices)
        item_vectors = self.item_embedding(item_indices)
        return {
            name: head.pair_logits(
                user_indices,
                item_indices,
                user_vectors,
                item_vectors,
            )
            for name, head in self.heads.items()
        }

    def preference_logits(
        self,
        user_indices: torch.Tensor,
        item_indices: torch.Tensor,
    ) -> torch.Tensor:
        user_vectors = self.user_embedding(user_indices)
        item_vectors = self.item_embedding(item_indices)
        return self.heads["preference"].pair_logits(
            user_indices,
            item_indices,
            user_vectors,
            item_vectors,
        )

    def all_item_preference_logits(self, user_indices: torch.Tensor) -> torch.Tensor:
        user_vectors = self.user_embedding(user_indices)
        return self.heads["preference"].all_item_logits(
            user_indices,
            user_vectors,
            self.item_embedding.weight,
        )

    def preference_scores(
        self,
        user_indices: torch.Tensor,
        item_indices: torch.Tensor,
    ) -> torch.Tensor:
        return torch.sigmoid(self.preference_logits(user_indices, item_indices))

    def all_item_preference_scores(self, user_indices: torch.Tensor) -> torch.Tensor:
        return torch.sigmoid(self.all_item_preference_logits(user_indices))
