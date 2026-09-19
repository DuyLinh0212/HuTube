from __future__ import annotations

from pydantic import BaseModel, ConfigDict, Field


class RecommendationRequest(BaseModel):
    model_config = ConfigDict(populate_by_name=True)

    user_id: str = Field(alias="userId", min_length=1)
    limit: int = Field(default=20, ge=1, le=100)
    exclude_item_ids: list[str] = Field(default_factory=list, alias="excludeItemIds")


class RecommendationItem(BaseModel):
    model_config = ConfigDict(populate_by_name=True)

    item_id: str = Field(alias="itemId")
    score: float


class RecommendationResponse(BaseModel):
    model_config = ConfigDict(populate_by_name=True)

    model_version: str = Field(alias="modelVersion")
    source: str
    items: list[RecommendationItem]


class HealthResponse(BaseModel):
    status: str
    service: str
    model_version: str | None = Field(default=None, alias="modelVersion")
    detail: str | None = None
