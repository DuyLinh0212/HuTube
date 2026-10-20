"""Verify that the committed delta manifest still matches a clause audit.

Usage:
  python coverage/verify_delta_scope.py outputs/.../master-clause-audit.json

This is deliberately a static verification: it never marks a scenario PASS and
never opens the browser.  It protects the no-rerun contract before a delta run
is scheduled.
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from support.delta_scope import load


def audited_groups(audit: dict) -> dict[str, set[str]]:
    result = {"allowed": set(), "excluded": set(), "retained": set()}
    for master in audit["masters"]:
        status = master["status"]
        if status == "PARTIAL_WITH_NAMED_GAPS":
            result["allowed"].add(master["id"])
        elif status == "OUT_OF_SCOPE":
            result["excluded"].add(master["id"])
        elif status == "PASS_RETAINED":
            result["retained"].add(master["id"])
        else:
            raise AssertionError(f"Unexpected master status for {master['id']}: {status}")
    return result


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("audit", type=Path)
    args = parser.parse_args()
    audit = json.loads(args.audit.read_text(encoding="utf-8"))
    scope = load()
    groups = audited_groups(audit)
    assert set(scope["allowed_parents"]) == groups["allowed"], "Manifest and audit remaining-gap parents differ."
    assert set(scope["excluded_parents"]) == groups["excluded"], "Manifest and audit exclusions differ."
    assert scope["retained_parent_count"] == len(groups["retained"]), "Retained count differs from audit."
    assert not groups["allowed"].intersection(groups["excluded"] | groups["retained"])
    print(json.dumps({"allowed": len(groups["allowed"]), "excluded": len(groups["excluded"]), "retained": len(groups["retained"])}, ensure_ascii=False))


if __name__ == "__main__":
    main()
