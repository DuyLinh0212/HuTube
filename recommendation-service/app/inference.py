from __future__ import annotations

import torch

from app.model_registry import LoadedModel
from app.ranking import blend_preference_with_popularity, normalized_popularity
from app.schemas import RecommendationItem


class UserNotInModelError(LookupError):
    pass


class InferenceEngine:
    def __init__(self, loaded: LoadedModel) -> None:
        self.loaded = loaded

    def recommend(
        self,
        *,
        user_id: str,
        limit: int,
        exclude_item_ids: list[str],
    ) -> list[RecommendationItem]:
        user_index = self.loaded.mappings.user_to_index.get(str(user_id))
        if user_index is None:
            raise UserNotInModelError(f"User {user_id} is not present in this model.")
        excluded = set(int(value) for value in self.loaded.seen_items(user_index))
        excluded.update(
            self.loaded.mappings.item_to_index[value]
            for value in {str(item) for item in exclude_item_ids}
            if value in self.loaded.mappings.item_to_index
        )
        model = self.loaded.model
        with torch.no_grad():
            users = torch.as_tensor(
                [user_index],
                dtype=torch.long,
                device=self.loaded.device,
            )
            scores = model.all_item_preference_scores(users).squeeze(0)
            if self.loaded.item_popularity is not None:
                scores = blend_preference_with_popularity(
                    scores.unsqueeze(0),
                    normalized_popularity(self.loaded.item_popularity),
                    popularity_weight=self.loaded.popularity_weight,
                ).squeeze(0)
            if excluded:
                indices = torch.as_tensor(
                    sorted(excluded),
                    dtype=torch.long,
                    device=self.loaded.device,
                )
                scores[indices] = -torch.inf
            available = int(torch.isfinite(scores).sum().item())
            count = min(limit, available)
            if count <= 0:
                return []
            values, indices = torch.topk(scores, k=count)
        return [
            RecommendationItem(
                itemId=self.loaded.index_to_item[int(item_index)],
                score=float(score),
            )
            for item_index, score in zip(
                indices.cpu().tolist(),
                values.cpu().tolist(),
                strict=True,
            )
        ]
