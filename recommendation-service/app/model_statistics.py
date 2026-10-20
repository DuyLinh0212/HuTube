"""Model inventory and last successful inference, persisted outside the serving path."""

from __future__ import annotations

import logging
import re
import threading
from concurrent.futures import ThreadPoolExecutor
from datetime import UTC, datetime

from botocore.exceptions import ClientError

from app.config import Settings
from app.r2_store import R2Store

logger = logging.getLogger(__name__)


def _version(value: object) -> str | None:
    return value if isinstance(value, str) and re.fullmatch(r"[\w.-]{1,200}", value) else None


def _timestamp(value: object) -> datetime:
    try:
        result = datetime.fromisoformat(str(value).replace("Z", "+00:00"))
        return result.replace(tzinfo=UTC) if result.tzinfo is None else result
    except ValueError:
        return datetime.min.replace(tzinfo=UTC)


class ModelStatistics:
    def __init__(self, settings: Settings) -> None:
        self.settings = settings
        self.pending: dict[str, str] = {}
        self.lock = threading.Lock()
        self.flush_lock = threading.Lock()

    def record_use(self, model_version: str) -> None:
        if _version(model_version):
            with self.lock:
                self.pending[model_version] = datetime.now(UTC).isoformat()

    def flush(self) -> None:
        # Inference only updates memory. R2 outages must not delay recommendations.
        if self.settings.missing_r2_settings or not self.flush_lock.acquire(blocking=False):
            return
        try:
            with self.lock:
                pending = dict(self.pending)
            if not pending:
                return
            store = R2Store(self.settings)
            for version, used_at in pending.items():
                key = f"collaborative_cf/usage/{version}.json"
                try:
                    for _ in range(3):
                        current, etag = store.read_versioned_json(key)
                        latest = max((current or {}).get("lastUsedAt"), used_at, key=_timestamp)
                        try:
                            store.compare_write_json(key, {"lastUsedAt": latest}, etag)
                            with self.lock:
                                if _timestamp(self.pending.get(version)) <= _timestamp(used_at):
                                    self.pending.pop(version, None)
                            break
                        except ClientError as exc:
                            if exc.response.get("Error", {}).get("Code") not in {
                                "PreconditionFailed", "412", "ConditionalRequestConflict", "409",
                            }:
                                raise
                except Exception:
                    logger.warning("Could not persist usage for model %s; will retry.", version,
                                   exc_info=True)
        except Exception:
            logger.warning("Could not flush model usage; will retry.", exc_info=True)
        finally:
            self.flush_lock.release()

    def catalog(self, manifest: dict | None, metadata: dict | None) -> dict:
        models: dict[str, dict] = {}
        active_version = _version((metadata or {}).get("modelVersion"))
        store = None
        if not self.settings.missing_r2_settings:
            store = R2Store(self.settings)
            # Existing durable training jobs also provide manifests for older builds.
            keys = store.list_keys("collaborative_cf/jobs/")
            keys += store.list_keys("collaborative_cf/models/")
            with ThreadPoolExecutor(max_workers=4) as pool:
                records = list(pool.map(store.read_json, keys))
            for record in records:
                if not record:
                    continue
                # Build manifests also carry jobId. Only job envelopes nest the
                # manifest; treating every jobId record as an envelope hides builds.
                value = record if "modelVersion" in record else record.get("manifest")
                version = _version((value or {}).get("modelVersion"))
                if version:
                    models[version] = {**models.get(version, {}), **value}
            published = store.read_json("collaborative_cf/active.json")
            if published and (version := _version(published.get("modelVersion"))):
                models[version] = {**models.get(version, {}), **published}
        if manifest and (version := _version(manifest.get("modelVersion"))):
            models[version] = {**models.get(version, {}), **manifest}
        if metadata and active_version:
            models[active_version] = {**metadata, **models.get(active_version, {})}
        ordered = sorted(models.values(), key=lambda x: _timestamp(
            x.get("buildCompletedAt") or x.get("updatedAt") or x.get("trainedAt")), reverse=True)
        with self.lock:
            pending = dict(self.pending)
        if store:
            with ThreadPoolExecutor(max_workers=4) as pool:
                usage = list(pool.map(store.read_json, [
                    f"collaborative_cf/usage/{m['modelVersion']}.json" for m in ordered
                ]))
        else:
            usage = [None] * len(ordered)
        items = []
        for model, saved_usage in zip(ordered, usage, strict=True):
            version = model["modelVersion"]
            last_used = max((saved_usage or {}).get("lastUsedAt"), pending.get(version),
                            key=_timestamp)
            items.append({
                "modelVersion": version,
                "modelAlgorithm": model.get("modelAlgorithm", "item_based"),
                "buildStartedAt": model.get("buildStartedAt"),
                "buildCompletedAt": model.get("buildCompletedAt") or model.get("updatedAt")
                    or model.get("trainedAt"),
                "buildDurationSeconds": model.get("buildDurationSeconds"),
                "fitDurationSeconds": model.get("fitDurationSeconds"),
                "usersCount": model.get("usersCount"),
                "videosCount": model.get("itemsCount"),
                "interactionsCount": model.get("interactionsCount"),
                "lastUsedAt": last_used,
                "isActive": version == active_version,
            })
        return {"activeModelVersion": active_version, "items": items}
