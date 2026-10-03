"""Fixture access is restricted to the runner's own local PostgreSQL database."""
import json
import os
import subprocess
from pathlib import Path

DATABASE = "hutube_e2e_runner"
DB_USER = "hutube_e2e"


class LocalDb:
    def __init__(self, config):
        self.bin = Path(config["postgres_bin"])
        self.port = str(config["pg_port"])

    def sql(self, sql, variables=None, database=DATABASE):
        if database not in (DATABASE, "postgres"):
            raise ValueError("Only the managed E2E database is allowed.")
        env = {k: v for k, v in os.environ.items() if not k.startswith("PG")}
        args = [str(self.bin / ("psql.exe" if os.name == "nt" else "psql")), "-X", "-qAt",
                "-v", "ON_ERROR_STOP=1", "-h", "127.0.0.1", "-p", self.port, "-U", DB_USER, "-d", database]
        for key, value in (variables or {}).items():
            args += ["-v", f"{key}={value}"]
        result = subprocess.run(args, input=sql, text=True, encoding="utf-8", capture_output=True,
                                env=env, timeout=30, creationflags=subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0)
        if result.returncode:
            raise RuntimeError("Local E2E fixture SQL failed: " + result.stderr[:500])
        return result.stdout.strip()

    def account(self, email):
        raw = self.sql("""SELECT json_build_object('user_id',u.user_id,'role_id',u.role_id,'role',r.code,
            'verified',u.email_verified_at IS NOT NULL,'status',u.status)
            FROM users u JOIN roles r ON r.role_id=u.role_id WHERE u.email=:'email'::citext AND u.deleted_at IS NULL;""", {"email": email})
        return json.loads(raw) if raw else None

    def grant_admin(self, user_id):
        self.sql("""UPDATE users SET role_id=(SELECT role_id FROM roles WHERE code='admin' AND status='active'), updated_at=now()
            WHERE user_id=:'id'::uuid AND status='active' AND email_verified_at IS NOT NULL;""", {"id": user_id})

    def restore_role(self, user_id, role_id):
        self.sql("UPDATE users SET role_id=:'role'::uuid,updated_at=now() WHERE user_id=:'id'::uuid;", {"id": user_id, "role": role_id})

    def account_count(self, email):
        return int(self.sql("SELECT count(*) FROM users WHERE email=:'email'::citext;", {"email": email}))
