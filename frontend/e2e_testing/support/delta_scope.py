"""Delta-only E2E scope validation.

The historical evidence catalogue is intentionally not imported at run time: it
is an artifact, not executable test input.  This small committed manifest is
the reviewed projection of that catalogue and fails closed when a delta run
tries to execute a retained or excluded parent scenario.
"""
from __future__ import annotations

import json
import os
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_SCOPE = ROOT / "coverage" / "delta-scope.json"
SCOPE_ENV = "HUTUBE_E2E_DELTA_SCOPE"


class DeltaScopeError(RuntimeError):
    """Raised before a retained scenario can be executed in a delta run."""


def enabled() -> bool:
    return os.environ.get(SCOPE_ENV, "").strip().lower() in {"1", "true", "yes"}


def load(path: Path = DEFAULT_SCOPE) -> dict:
    data = json.loads(path.read_text(encoding="utf-8"))
    return validate(data)


def validate(data: dict) -> dict:
    """Validate already-decoded manifest data (kept pure for unit tests)."""
    allowed = data.get("allowed_parents")
    excluded = data.get("excluded_parents")
    if not isinstance(allowed, dict) or not allowed or not isinstance(excluded, dict):
        raise DeltaScopeError("Delta scope manifest is malformed.")
    if set(allowed).intersection(excluded):
        raise DeltaScopeError("A parent cannot be both delta-allowed and excluded.")
    return data


def assert_allowed(parent: str, case_id: str, path: Path = DEFAULT_SCOPE) -> None:
    """Fail closed unless *parent* is one of the reviewed remaining gaps."""
    if not enabled():
        return
    scope = load(path)
    retained_path = ROOT / 'coverage/retained-evidence.json'
    if not retained_path.exists():
        raise DeltaScopeError('Freeze retained case evidence before executing delta cases.')
    retained = json.loads(retained_path.read_text(encoding='utf-8'))['cases']
    if case_id in retained:
        raise DeltaScopeError(f'{case_id} already has PASS evidence; select only a new missing assertion.')
    delta_passes = ROOT / 'coverage/delta-passed-evidence.json'
    if delta_passes.exists() and case_id in json.loads(delta_passes.read_text(encoding='utf-8'))['cases']:
        raise DeltaScopeError(f'{case_id} already passed in delta evidence; rerun is refused.')
    if parent in scope["excluded_parents"]:
        raise DeltaScopeError(f"{case_id} targets excluded scenario {parent}.")
    if parent not in scope["allowed_parents"]:
        raise DeltaScopeError(
            f"{case_id} targets retained or unreviewed scenario {parent}; "
            "delta runs may execute only listed gaps."
        )


def summary(path: Path = DEFAULT_SCOPE) -> dict:
    scope = load(path)
    return {
        "allowed_parent_count": len(scope["allowed_parents"]),
        "excluded_parent_count": len(scope["excluded_parents"]),
        "retained_parent_count": scope["retained_parent_count"],
        "allowed_parents": sorted(scope["allowed_parents"]),
    }
