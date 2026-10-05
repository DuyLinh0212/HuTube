"""Own local servers + persistent test database. Run --help before first use."""
import argparse
import json
import os
import shlex
import shutil
import socket
import subprocess
import sys
import time
from datetime import datetime, timezone
from pathlib import Path
from urllib.parse import urlsplit
from urllib.request import urlopen

from support.local_db import LocalDb, DATABASE, DB_USER
from support.state import RunLock, atomic_json

ROOT = Path(__file__).resolve().parent
REPO = ROOT.parents[1]
HIDDEN = subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0


def validate(config):
    for key in ("user_url", "admin_url", "api_url"):
        uri = urlsplit(config[key])
        expected_path = "/api/v1" if key == "api_url" else ""
        if uri.scheme != "http" or uri.hostname != "127.0.0.1" or not uri.port or uri.username or uri.query or uri.fragment or uri.path.rstrip("/") != expected_path:
            raise ValueError(f"{key} must be a 127.0.0.1 HTTP URL with a port and the expected path.")
    ports = [urlsplit(config[k]).port for k in ("user_url", "admin_url", "api_url")] + [config["pg_port"]]
    if len(set(ports)) != 4 or not all(1024 <= p <= 65535 for p in ports):
        raise ValueError("Choose four distinct non-system ports.")
    if not config["account"]["email"].endswith("@example.test"):
        raise ValueError("Managed local tests require a synthetic @example.test account.")


def wait_health(url, process, timeout):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if process.poll() is not None:
            raise RuntimeError("A managed server stopped. See its log in this run directory.")
        try:
            with urlopen(url, timeout=2) as response:
                if response.status == 200:
                    return
        except (OSError, TimeoutError):
            pass
        time.sleep(0.25)
    raise TimeoutError("Server readiness timed out: " + url)


def stop_process(process):
    if process.poll() is not None:
        return
    if os.name == "nt":
        subprocess.run(["taskkill", "/PID", str(process.pid), "/T", "/F"], capture_output=True, creationflags=HIDDEN, timeout=15)
    else:
        process.terminate()
    try:
        process.wait(timeout=10)
    except subprocess.TimeoutExpired:
        process.kill(); process.wait(timeout=5)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", type=Path, default=ROOT / "config.example.json")
    parser.add_argument("--reuse-build", action="store_true", help="Use existing backend binaries and Angular builds; do not use after source edits.")
    parser.add_argument("--state-dir", type=Path, default=ROOT / ".state", help="Keep the same folder across runs to reuse the account.")
    args = parser.parse_args()
    config = json.loads(args.config.read_text(encoding="utf-8"))
    if os.environ.get("E2E_POSTGRES_BIN"):
        config["postgres_bin"] = os.environ["E2E_POSTGRES_BIN"]
    validate(config)
    state = args.state_dir.resolve()
    state.mkdir(parents=True, exist_ok=True)
    run = ROOT / "artifacts/runs" / datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S.%fZ")
    run.mkdir(parents=True, exist_ok=False)
    config.update(state_dir=str(state), run_dir=str(run))
    runtime = state / "runtime.json"
    programs, handles = [], []
    pg_started = False
    pg_root = state / "postgres"
    pg_bin = Path(config["postgres_bin"])
    executable = lambda name: str(pg_bin / (name + ".exe" if os.name == "nt" else name))

    def checked(args, log, cwd=REPO, env=None, timeout=180):
        with (run / log).open("w", encoding="utf-8") as handle:
            result = subprocess.run(args, cwd=cwd, env=env, stdout=handle, stderr=subprocess.STDOUT, timeout=timeout, creationflags=HIDDEN)
        if result.returncode:
            raise RuntimeError(f"Command failed; see {log}.")

    def server(args, log, cwd=REPO, env=None):
        handle = (run / log).open("w", encoding="utf-8"); handles.append(handle)
        process = subprocess.Popen(args, cwd=cwd, env=env, stdout=handle, stderr=subprocess.STDOUT, creationflags=HIDDEN)
        programs.append(process)
        return process

    with RunLock(state / "run.lock"):
        atomic_json(runtime, config)
        try:
            # Refuse to connect to an API/web service already occupying our ports.
            for key in ("user_url", "admin_url", "api_url"):
                with socket.socket() as sock:
                    sock.bind(("127.0.0.1", urlsplit(config[key]).port))
            if not (pg_bin / ("pg_ctl.exe" if os.name == "nt" else "pg_ctl")).is_file():
                raise RuntimeError("PostgreSQL binaries missing. Set E2E_POSTGRES_BIN.")
            if not (pg_root / "PG_VERSION").exists():
                with socket.socket() as sock:
                    sock.bind(("127.0.0.1", config["pg_port"]))
                checked([executable("initdb"), "-D", str(pg_root), "-U", DB_USER, "--auth=trust", "--encoding=UTF8", "--locale=C"], "postgres-init.log")
            status = subprocess.run([executable("pg_ctl"), "-D", str(pg_root), "status"], capture_output=True, creationflags=HIDDEN)
            if status.returncode == 3:
                # Distribution packages can default to a postgres-owned Unix socket directory.
                # This cluster belongs to the current user; all clients connect over TCP.
                options = f"-h 127.0.0.1 -p {config['pg_port']}"
                if os.name != "nt":
                    options += f" -k {shlex.quote(str(pg_root))}"
                try:
                    checked([executable("pg_ctl"), "-D", str(pg_root), "-l", str(run / "postgres.log"), "-o", options, "-w", "-t", "30", "start"], "postgres-start.log", timeout=40)
                except (RuntimeError, subprocess.TimeoutExpired) as exc:
                    server_log = run / "postgres.log"
                    details = server_log.read_text(encoding="utf-8", errors="replace")[-3000:] if server_log.exists() else "PostgreSQL produced no server log."
                    raise RuntimeError(f"{exc}\nPostgreSQL server log:\n{details}") from exc
                pg_started = True
            elif status.returncode != 0:
                raise RuntimeError("Cannot inspect managed PostgreSQL cluster.")
            metadata = (pg_root / "postmaster.pid").read_text().splitlines()
            if metadata[3] != str(config["pg_port"]):
                raise RuntimeError("Managed PostgreSQL cluster runs on a different port.")
            db = LocalDb(config)
            if db.sql("SELECT 1 FROM pg_database WHERE datname='hutube_e2e_runner';", database="postgres") != "1":
                db.sql(f"CREATE DATABASE {DATABASE};", database="postgres")
            env = {k: v for k, v in os.environ.items() if not k.startswith(("ConnectionStrings__", "Jwt__", "Email__", "Storage__", "Auth__", "Google__", "Recommendation__", "SePay__"))}
            env.update(ASPNETCORE_ENVIRONMENT="Development", DOTNET_ENVIRONMENT="Development",
                       ConnectionStrings__Database=f"Host=127.0.0.1;Port={config['pg_port']};Username={DB_USER};Database={DATABASE}",
                       Jwt__SigningKey="HuTubeE2eOnlySyntheticSigningKey2026_DoNotUseInProduction",
                       Email__Mode="Pickup", Email__PickupDirectory=str(state / "mail"),
                       Auth__WebBaseUrl=config["user_url"], Auth__AdminBaseUrl=config["admin_url"],
                       Google__ClientId="", Recommendation__Enabled="false", Storage__Provider="Local",
                       Storage__R2__CredentialsFile=str(state / "unused-r2-credentials"),
                       VideoProcessing__Enabled="false", CfSeedUpload__Directory=str(state / "chunks"))
            api_project = REPO / "backend/src/HuTube.Api"
            dll = api_project / "bin/Debug/net10.0/HuTube.Api.dll"
            if not args.reuse_build:
                checked(["dotnet", "build", str(api_project)], "backend-build.log")
                for app in ("user", "admin"):
                    command = ["cmd.exe", "/d", "/c", "npm", "run", "build"] if os.name == "nt" else ["npm", "run", "build"]
                    checked(command, f"{app}-build.log", REPO / f"frontend/{app}-web")
            if not dll.exists():
                raise RuntimeError("Build API first, or remove --reuse-build.")
            checked(["dotnet", str(dll), "--migrate"], "migrate.log", api_project, env)
            api_origin = config["api_url"].removesuffix("/api/v1")
            api = server(["dotnet", str(dll), "--urls", api_origin], "api.log", api_project, env)
            wait_health(api_origin + "/health", api, config["startup_seconds"])
            # Exact endpoint inventory for the backend test plan, without JWT or data responses.
            with urlopen(api_origin + "/openapi/v1.json", timeout=30) as response:
                atomic_json(run / "openapi.json", json.load(response))
            for app in ("user", "admin"):
                web_root = REPO / f"frontend/{app}-web/dist/{app}-web/browser"
                if not (web_root / "index.html").exists():
                    raise RuntimeError(f"Missing {app} Angular build.")
                web = server([sys.executable, str(ROOT / "support/serve.py"), "--root", str(web_root), "--port", str(urlsplit(config[app + '_url']).port), "--api-url", config["api_url"], "--user-url", config["user_url"]], f"{app}-server.log")
                wait_health(config[app + "_url"] + "/login", web, config["startup_seconds"])
            child = server([sys.executable, str(ROOT / "tests/auth.py"), "--config", str(runtime)], "auth.log", ROOT, {**os.environ, "PYTHONIOENCODING": "utf-8"})
            try:
                code = child.wait(timeout=config["suite_seconds"])
            except subprocess.TimeoutExpired:
                stop_process(child)
                raise TimeoutError("Auth suite exceeded its wall-clock budget; state is retained for recovery.") from None
            print(f"Artifacts: {run}", flush=True)
            if code:
                raise RuntimeError("Auth cases failed; inspect report.json, screenshots and auth.log.")
            report = json.loads((run / "report.json").read_text(encoding="utf-8"))
            print(f"PASS: {report['passed']} cases; {report['reused']} prerequisites reused; account_count={report['account_count']}", flush=True)
        finally:
            for process in reversed(programs):
                stop_process(process)
            for handle in handles:
                handle.close()
            if pg_started:
                checked([executable("pg_ctl"), "-D", str(pg_root), "-m", "fast", "-w", "-t", "30", "stop"], "postgres-stop.log", timeout=40)


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        print(f"FAIL: {exc}", file=sys.stderr)
        sys.exit(1)
