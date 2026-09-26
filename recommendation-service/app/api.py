from __future__ import annotations

import secrets

from fastapi import APIRouter, Header, HTTPException, Request, status

from app.inference import InferenceEngine, UserNotInModelError
from app.schemas import HealthResponse, RecommendationRequest, RecommendationResponse

router = APIRouter()


def _error(status_code: int, code: str, message: str, retryable: bool) -> HTTPException:
    return HTTPException(
        status_code=status_code,
        detail={"code": code, "message": message, "retryable": retryable},
    )


@router.get("/health", response_model=HealthResponse)
async def health(request: Request) -> HealthResponse:
    settings = request.app.state.settings
    registry = request.app.state.registry
    version = (
        str(registry.loaded.metadata.get("modelVersion"))
        if registry.loaded is not None
        else None
    )
    return HealthResponse(
        status="ok",
        service=settings.app_name,
        modelVersion=version,
    )


@router.get("/ready", response_model=HealthResponse)
async def ready(request: Request) -> HealthResponse:
    settings = request.app.state.settings
    registry = request.app.state.registry
    if registry.loaded is None or not settings.recommender_service_token:
        detail = registry.load_error or "RECOMMENDER_SERVICE_TOKEN is not configured."
        raise _error(
            status.HTTP_503_SERVICE_UNAVAILABLE,
            "SERVICE_NOT_READY",
            detail,
            True,
        )
    return HealthResponse(
        status="ready",
        service=settings.app_name,
        modelVersion=str(registry.loaded.metadata.get("modelVersion")),
    )


@router.post(
    "/internal/recommendations",
    response_model=RecommendationResponse,
    response_model_by_alias=True,
)
async def recommendations(
    payload: RecommendationRequest,
    request: Request,
    service_token: str | None = Header(default=None, alias="X-Service-Token"),
) -> RecommendationResponse:
    settings = request.app.state.settings
    expected = settings.recommender_service_token
    if (
        not expected
        or service_token is None
        or not secrets.compare_digest(service_token, expected)
    ):
        raise _error(
            status.HTTP_401_UNAUTHORIZED,
            "INVALID_SERVICE_TOKEN",
            "A valid X-Service-Token is required.",
            False,
        )
    registry = request.app.state.registry
    if registry.loaded is None:
        raise _error(
            status.HTTP_503_SERVICE_UNAVAILABLE,
            "MODEL_NOT_READY",
            registry.load_error or "No model is loaded.",
            True,
        )
    try:
        items = InferenceEngine(registry.loaded).recommend(
            user_id=payload.user_id,
            limit=payload.limit,
            exclude_item_ids=payload.exclude_item_ids,
        )
    except UserNotInModelError as exc:
        raise _error(
            status.HTTP_404_NOT_FOUND,
            "USER_NOT_IN_MODEL",
            str(exc),
            False,
        ) from exc
    metadata = registry.loaded.metadata
    return RecommendationResponse(
        modelVersion=str(metadata["modelVersion"]),
        source=str(metadata["source"]),
        items=items,
    )


@router.post("/internal/reload")
async def reload_model(request: Request):
    registry = request.app.state.registry
    registry.load()
    version = (
        str(registry.loaded.metadata.get("modelVersion"))
        if registry.loaded is not None
        else None
    )
    return {"status": "ok", "modelVersion": version}

