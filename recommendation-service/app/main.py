from __future__ import annotations

from contextlib import asynccontextmanager

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
            resolved_registry.load()
        yield

    app = FastAPI(
        title=resolved_settings.app_name,
        version="0.1.0",
        description="Internal MBMF inference service for HuTube.",
        lifespan=lifespan,
    )
    app.state.settings = resolved_settings
    app.state.registry = resolved_registry
    app.include_router(router)
    return app


app = create_app()
