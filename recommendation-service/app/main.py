from __future__ import annotations

import asyncio
import logging
from contextlib import asynccontextmanager, suppress

from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse

from app.api import router
from app.config import Settings, get_settings
from app.model_registry import ModelRegistry
from app.r2_store import R2ConfigurationError

logger = logging.getLogger("uvicorn.error")


def create_app(
    settings: Settings | None = None,
    registry: ModelRegistry | None = None,
) -> FastAPI:
    resolved_settings = settings or get_settings()
    resolved_registry = registry or ModelRegistry(resolved_settings)

    @asynccontextmanager
    async def lifespan(_app: FastAPI):
        if resolved_registry.loaded is None:
            await asyncio.to_thread(resolved_registry.load)
        async def refresh_models():
            delay = 2
            while True:
                await asyncio.sleep(delay)
                await asyncio.to_thread(resolved_registry.refresh)
                delay = 10 if resolved_registry.loaded is not None else min(delay * 2, 60)
        task = asyncio.create_task(refresh_models())
        try:
            yield
        finally:
            task.cancel()
            with suppress(asyncio.CancelledError):
                await task

    app = FastAPI(
        title=resolved_settings.app_name,
        version="0.1.0",
        description=(
            "Internal pure Collaborative Filtering service for HuTube. "
            "Supports User-Based and Item-Based CF."
        ),
        lifespan=lifespan,
    )
    app.state.settings = resolved_settings
    app.state.registry = resolved_registry

    @app.exception_handler(R2ConfigurationError)
    async def missing_model_storage(request: Request, exc: R2ConfigurationError):
        logger.error("Model request %s cannot use R2; missing settings: %s",
                     request.url.path, ", ".join(exc.missing_settings))
        return JSONResponse(status_code=503, content={"detail": {
            "code": "MODEL_STORAGE_NOT_CONFIGURED",
            "message": str(exc) + ". Configure them on the Recommendation Service in Render.",
            "retryable": False,
            "missingSettings": exc.missing_settings,
        }})

    @app.exception_handler(Exception)
    async def unexpected_model_error(request: Request, exc: Exception):
        logger.error("Unhandled Recommendation Service error at %s", request.url.path,
                     exc_info=(type(exc), exc, exc.__traceback__))
        return JSONResponse(status_code=500, content={"detail": {
            "code": "MODEL_SERVICE_ERROR",
            "message": "Recommendation Service failed; inspect its error logs.",
            "retryable": False,
            "errorType": type(exc).__name__,
        }})

    app.include_router(router)
    return app


app = create_app()
