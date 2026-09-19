from __future__ import annotations

from datetime import datetime
from enum import StrEnum

from pydantic import BaseModel, ConfigDict, field_validator


class InteractionSource(StrEnum):
    MOVIELENS = "MOVIELENS"
    BOT = "BOT"
    REAL = "REAL"


class BehaviorMasks(BaseModel):
    model_config = ConfigDict(frozen=True)

    rating: int
    like: int
    dislike: int
    comment: int
    share: int
    watch_ratio: int


class UnifiedInteraction(BaseModel):
    """One normalized User-Item observation shared by benchmark and production pipelines."""

    model_config = ConfigDict(frozen=True)

    user_id: str
    item_id: str
    rating: float | None = None
    like: bool | None = None
    dislike: bool | None = None
    comment: bool | None = None
    share: bool | None = None
    watch_ratio: float | None = None
    source: InteractionSource
    timestamp: datetime

    @field_validator("user_id", "item_id")
    @classmethod
    def validate_identifier(cls, value: str) -> str:
        normalized = str(value).strip()
        if not normalized:
            raise ValueError("Identifier must not be blank.")
        return normalized

    @field_validator("rating")
    @classmethod
    def validate_rating(cls, value: float | None) -> float | None:
        if value is not None and not 1.0 <= value <= 5.0:
            raise ValueError("rating must be between 1 and 5.")
        return value

    @field_validator("watch_ratio")
    @classmethod
    def validate_watch_ratio(cls, value: float | None) -> float | None:
        if value is not None and not 0.0 <= value <= 1.0:
            raise ValueError("watch_ratio must be between 0 and 1.")
        return value

    @property
    def masks(self) -> BehaviorMasks:
        return BehaviorMasks(
            rating=int(self.rating is not None),
            like=int(self.like is not None),
            dislike=int(self.dislike is not None),
            comment=int(self.comment is not None),
            share=int(self.share is not None),
            watch_ratio=int(self.watch_ratio is not None),
        )
