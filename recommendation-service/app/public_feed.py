from __future__ import annotations

import logging
from collections import OrderedDict
from threading import Lock
from time import monotonic
from typing import Annotated

import httpx
from fastapi import APIRouter, Header, Query, Request
from fastapi.responses import JSONResponse
from starlette.concurrency import run_in_threadpool

from app.inference import InferenceEngine, UserNotInModelError

router = APIRouter()
logger = logging.getLogger("uvicorn.error")
_rank_cache: OrderedDict[tuple, tuple[float, tuple[str, ...]]] = OrderedDict()
_rank_lock = Lock()


def _rank(registry, context: dict) -> list[str]:
    loaded = registry.loaded
    if not context["enabled"] or loaded is None:
        return []
    # Identity and excludes come from the authenticated content API, never from
    # a client-supplied user ID. A model swap creates a different partition.
    key = (id(loaded), loaded.metadata["modelVersion"], context["userId"],
           tuple(sorted(context["excludeItemIds"])))
    with _rank_lock:
        cached = _rank_cache.get(key)
        if cached is not None and cached[0] > monotonic():
            _rank_cache.move_to_end(key)
            registry.statistics.record_use(str(loaded.metadata["modelVersion"]))
            return list(cached[1])
        _rank_cache.pop(key, None)
    try:
        items = InferenceEngine(loaded).recommend(
            user_id=context["userId"], limit=100,
            exclude_item_ids=context["excludeItemIds"],
        )
        registry.statistics.record_use(str(loaded.metadata["modelVersion"]))
        ids = tuple(item.item_id for item in items)
        with _rank_lock:
            if len(_rank_cache) >= 500:
                _rank_cache.popitem(last=False)
            _rank_cache[key] = (monotonic() + 30, ids)
        return list(ids)
    except UserNotInModelError:
        return []
    except Exception:
        logger.exception("Recommendation inference failed; serving the catalogue fallback.")
        return []


@router.get("/api/v1/feed/recommended")
async def recommended_feed(
    request: Request,
    authorization: Annotated[str | None, Header()] = None,
    page: Annotated[int, Query(ge=1)] = 1,
    page_size: Annotated[int, Query(alias="pageSize", ge=1, le=100)] = 20,
) -> JSONResponse:
    """Serve web/mobile directly; the content API supplies identity and video data only."""
    no_store = {"Cache-Control": "no-store"}
    if not authorization or not authorization.lower().startswith("bearer "):
        return JSONResponse(status_code=401, headers=no_store, content={
            "code": "SESSION_EXPIRED", "message": "A valid access token is required.",
        })

    # The content API validates the JWT AND the active session. Never trust a userId
    # supplied by the client, or expose the internal inference/admin tokens to it.
    headers = {"Authorization": authorization}
    settings = request.app.state.settings
    if settings.recommender_service_token and request.client:
        headers["X-Service-Token"] = settings.recommender_service_token
        headers["X-Recommendation-Client-IP"] = request.client.host
    client_platform = request.headers.get("X-HuTube-Client")
    if client_platform in {"web", "mobile"}:
        headers["X-HuTube-Client"] = client_platform
    base = str(settings.hutube_api_base_url).rstrip("/")
    try:
        client = request.app.state.content_client
        context_response = await client.get(f"{base}/feed/recommendation-context", headers=headers)
        if not context_response.is_success:
            return JSONResponse(status_code=context_response.status_code,
                                headers=no_store, content=context_response.json())
        video_ids = await run_in_threadpool(
            _rank, request.app.state.registry, context_response.json(),
        )
        response = await client.post(f"{base}/feed/resolve", headers=headers, json={
            "videoIds": video_ids, "page": page, "pageSize": page_size,
        })
        return JSONResponse(status_code=response.status_code, headers=no_store,
                            content=response.json())
    except (httpx.HTTPError, ValueError):
        logger.exception("The content API could not serve the recommendation feed.")
        return JSONResponse(status_code=503, headers=no_store, content={
            "code": "CONTENT_API_UNAVAILABLE", "message": "Video data is temporarily unavailable.",
        })
