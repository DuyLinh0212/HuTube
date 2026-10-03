"""Persistent account checkpoint and a process lock; never generate random accounts."""
import json
import os
from datetime import datetime, timezone
from pathlib import Path


def now():
    return datetime.now(timezone.utc).isoformat()


def atomic_json(path: Path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")
    os.replace(temporary, path)


class Checkpoint:
    def __init__(self, path, scope, account):
        self.path = path
        self.data = json.loads(path.read_text(encoding="utf-8")) if path.exists() else {
            "version": 1, "scope": scope, "account": account, "resources": {}, "flows": {}
        }
        if self.data["scope"] != scope or self.data["account"]["email"] != account["email"]:
            raise RuntimeError("Checkpoint belongs to another environment/account. Keep its state; use a separate state directory.")
        # A password changed by a later reset/password flow remains authoritative.
        self.account = self.data["account"]
        self.save()

    def save(self):
        self.data["updated_at"] = now()
        atomic_json(self.path, self.data)

    def record(self, case_id, evidence, status="passed"):
        prior = self.data["flows"].get(case_id, {})
        first = prior.get("first_passed_evidence") or (prior.get("evidence") if prior.get("status") == "passed" else None)
        self.data["flows"][case_id] = {"status": status, "evidence": evidence, "at": now(),
                                      "first_passed_evidence": first or (evidence if status == "passed" else None)}
        self.save()


class RunLock:
    """OS lock is released even on process crash; an existing file is not a stale lock."""
    def __init__(self, path):
        path.parent.mkdir(parents=True, exist_ok=True)
        self.file = path.open("a+b")
        self.file.seek(0)
        if path.stat().st_size == 0:
            self.file.write(b"0"); self.file.flush()
        self.file.seek(0)
        try:
            if os.name == "nt":
                import msvcrt
                msvcrt.locking(self.file.fileno(), msvcrt.LK_NBLCK, 1)
            else:
                import fcntl
                fcntl.flock(self.file, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except OSError:
            self.file.close()
            raise RuntimeError("Another E2E run is using this checkpoint. Run one account worker at a time.") from None

    def __enter__(self):
        return self

    def __exit__(self, *args):
        self.file.close()
