from __future__ import annotations

from app.model_registry import LoadedModel
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
        excluded = {
            self.loaded.mappings.item_to_index[value]
            for value in {str(item) for item in exclude_item_ids}
            if value in self.loaded.mappings.item_to_index
        }
        ranked = self.loaded.model.recommend(
            user_index,
            limit=limit,
            exclude_item_indices=excluded,
        )
        return [
            RecommendationItem(
                itemId=self.loaded.index_to_item[item_index],
                score=score,
            )
            for item_index, score in ranked
        ]
