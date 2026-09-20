from __future__ import annotations

from functools import lru_cache
from pathlib import Path
from typing import Literal

from pydantic_settings import BaseSettings, SettingsConfigDict

SERVICE_ROOT = Path(__file__).resolve().parents[1]


class Settings(BaseSettings):
    app_name: str = "HuTube Pure Collaborative Filtering Service"
    app_env: str = "development"
    model_storage_path: Path = Path("data/artifacts")
    model_version: str = "benchmark-latest"
    model_type: Literal["user_based", "item_based"] = "item_based"
    recommender_service_token: str = ""
    allow_benchmark_model: bool = False

    model_config = SettingsConfigDict(
        env_file=SERVICE_ROOT / ".env",
        env_file_encoding="utf-8",
        case_sensitive=False,
        extra="ignore",
    )

    @property
    def resolved_model_storage_path(self) -> Path:
        path = self.model_storage_path
        return path if path.is_absolute() else (SERVICE_ROOT / path).resolve()


@lru_cache
def get_settings() -> Settings:
    return Settings()
