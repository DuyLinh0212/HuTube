from __future__ import annotations

import asyncio
import secrets
from typing import Literal
from uuid import uuid4

from fastapi import APIRouter, Header, HTTPException, Request, status
from fastapi.responses import JSONResponse
from pydantic import BaseModel, Field
from starlette.concurrency import run_in_threadpool

from app.inference import InferenceEngine, UserNotInModelError
from app.schemas import HealthResponse, RecommendationRequest, RecommendationResponse

router = APIRouter()


class ScoreAggregationRequest(BaseModel):
    mode: Literal["average", "weighted"] = "average"
    weights: dict[str, float] = Field(default_factory=dict)


class TrainRequest(BaseModel):
    csv_key: str = Field(alias="csvKey", min_length=1)
    csv_sha256: str = Field(alias="csvSha256", min_length=64, max_length=64)
    score_aggregation: ScoreAggregationRequest = Field(
        default_factory=ScoreAggregationRequest,
        alias="scoreAggregation",
    )


def _require_admin(request: Request, token: str | None) -> None:
    expected = request.app.state.settings.recommender_admin_token
    if not expected or token is None or not secrets.compare_digest(token, expected):
        raise _error(401, "INVALID_ADMIN_TOKEN", "A valid model admin token is required.", False)


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
        csvKey=registry.manifest.get("csvKey") if registry.manifest else None,
        csvSha256=registry.manifest.get("csvSha256") if registry.manifest else None,
        updatedAt=registry.manifest.get("updatedAt") if registry.manifest else None,
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
        csvKey=registry.manifest.get("csvKey") if registry.manifest else None,
        csvSha256=registry.manifest.get("csvSha256") if registry.manifest else None,
        updatedAt=registry.manifest.get("updatedAt") if registry.manifest else None,
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
    loaded = registry.loaded
    if loaded is None:
        raise _error(
            status.HTTP_503_SERVICE_UNAVAILABLE,
            "MODEL_NOT_READY",
            registry.load_error or "No model is loaded.",
            True,
        )
    try:
        items = InferenceEngine(loaded).recommend(
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
    metadata = loaded.metadata
    return RecommendationResponse(
        modelVersion=str(metadata["modelVersion"]),
        source=str(metadata["source"]),
        items=items,
    )


@router.get("/internal/model")
async def model_status(request: Request,
                       admin_token: str | None = Header(default=None, alias="X-Model-Admin-Token")):
    _require_admin(request, admin_token)
    registry = request.app.state.registry
    return {"status": "ready" if registry.loaded else "uninitialized",
            "manifest": registry.manifest, "loadError": registry.load_error}


@router.post("/internal/model/train")
async def train_model(payload: TrainRequest, request: Request,
                      admin_token: str | None = Header(default=None, alias="X-Model-Admin-Token")):
    _require_admin(request, admin_token)
    registry = request.app.state.registry
    if registry.update_task is not None and not registry.update_task.done():
        raise _error(409, "TRAINING_UNAVAILABLE", "A model update is already running.", True)
    job_id = str(uuid4())
    registry.update_jobs = {job_id: {"jobId": job_id, "status": "running",
                                      "csvKey": payload.csv_key, "csvSha256": payload.csv_sha256,
                                      "scoreAggregation": payload.score_aggregation.model_dump()}}

    async def work() -> None:
        try:
            manifest = await run_in_threadpool(registry.train_from_r2,
                                               payload.csv_key, payload.csv_sha256,
                                               payload.score_aggregation.model_dump())
            registry.update_jobs[job_id] = {"jobId": job_id, "status": "completed",
                                            "manifest": manifest}
        except Exception as exc:
            registry.update_jobs[job_id] = {"jobId": job_id, "status": "failed",
                                            "error": str(exc)}

    registry.update_task = asyncio.create_task(work())
    return JSONResponse(status_code=202, content={"jobId": job_id, "status": "running"})


@router.get("/internal/model/jobs/{job_id}")
async def model_job(job_id: str, request: Request,
                    admin_token: str | None = Header(default=None, alias="X-Model-Admin-Token")):
    _require_admin(request, admin_token)
    job = request.app.state.registry.update_jobs.get(job_id)
    if job is None:
        raise _error(
            404, "MODEL_JOB_NOT_FOUND", "Model job is not available in this process.", True
        )
    return job
