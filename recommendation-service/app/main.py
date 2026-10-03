from __future__ import annotations

from contextlib import asynccontextmanager
import asyncio
from contextlib import suppress

from fastapi import FastAPI

from app.api import router
from app.config import Settings, get_settings
from app.model_registry import ModelRegistry


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
    app.include_router(router)
    return app


app = create_app()
