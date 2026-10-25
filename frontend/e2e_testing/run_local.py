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
        allowed_hosts = ('127.0.0.1', 'localhost') if config.get('google_probe') else ('127.0.0.1',)
        if uri.scheme != "http" or uri.hostname not in allowed_hosts or not uri.port or uri.username or uri.query or uri.fragment or uri.path.rstrip("/") != expected_path:
            raise ValueError(f"{key} must be a 127.0.0.1 HTTP URL with a port and the expected path.")
    ports = [urlsplit(config[k]).port for k in ("user_url", "admin_url", "api_url")] + [config["pg_port"]]
    if len(set(ports)) != 4 or not all(1024 <= p <= 65535 for p in ports):
        raise ValueError("Choose four distinct non-system ports.")
    if not config["account"]["email"].endswith("@example.test"):
        raise ValueError("Managed local tests require a synthetic @example.test account.")


def assert_port_available(port):
    with socket.socket() as sock:
        if os.name == "nt":
            # Windows SO_REUSEADDR can take over an occupied address. Keep the
            # exclusive check there; POSIX reuse only ignores closed connections.
            sock.setsockopt(socket.SOL_SOCKET, socket.SO_EXCLUSIVEADDRUSE, 1)
        else:
            sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        try:
            sock.bind(("127.0.0.1", port))
        except OSError as error:
            raise RuntimeError(f"E2E port {port} is unavailable; stop its listener or choose another port.") from error


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
    parser.add_argument("--suite", choices=("auth", "web", "full", "rbac"), default="auth", help="Run auth, web, expanded functional or the 50-permission RBAC matrix.")
    parser.add_argument("--groups",default="auth-deep",help="Groups for the expanded full suite.")
    parser.add_argument("--delta-only",action="store_true",help="Run only reviewed scenario gaps; fail before executing retained or excluded parent scenarios.")
    parser.add_argument("--resume-run",help="Resume synthetic fixtures from an interrupted expanded run ID; no prior case is counted as newly executed.")
    parser.add_argument("--headed",action="store_true",help="Show the real browser for native fullscreen/PiP checks in the full suite.")
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
    events = []

    def event(phase, **details):
        events.append({'at': datetime.now(timezone.utc).isoformat(), 'phase': phase, **details})
        atomic_json(run / 'runner-events.json', events)
        print('E2E ' + phase + (' ' + details['log'] if 'log' in details else ''), flush=True)

    def checked(args, log, cwd=REPO, env=None, timeout=180):
        event('command-start', log=log)
        with (run / log).open("w", encoding="utf-8") as handle:
            result = subprocess.run(args, cwd=cwd, env=env, stdout=handle, stderr=subprocess.STDOUT, timeout=timeout, creationflags=HIDDEN)
        if result.returncode:
            event('command-failed', log=log, exit_code=result.returncode)
            raise RuntimeError(f"Command failed; see {log}.")
        event('command-complete', log=log, exit_code=result.returncode)

    def server(args, log, cwd=REPO, env=None):
        handle = (run / log).open("w", encoding="utf-8"); handles.append(handle)
        process = subprocess.Popen(args, cwd=cwd, env=env, stdout=handle, stderr=subprocess.STDOUT, creationflags=HIDDEN)
        programs.append(process)
        event('process-start', log=log, pid=process.pid)
        return process

    with RunLock(state / "run.lock"):
        atomic_json(runtime, config)
        try:
            # Refuse to connect to an API/web service already occupying our ports.
            for key in ("user_url", "admin_url", "api_url"):
                assert_port_available(urlsplit(config[key]).port)
            if not (pg_bin / ("pg_ctl.exe" if os.name == "nt" else "pg_ctl")).is_file():
                raise RuntimeError("PostgreSQL binaries missing. Set E2E_POSTGRES_BIN.")
            if not (pg_root / "PG_VERSION").exists():
                assert_port_available(config["pg_port"])
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
                       RabbitMq__Enabled="false", Fcm__Enabled="false",
                       VideoProcessing__Enabled="true" if args.suite in ("web","full") else "false", CfSeedUpload__Directory=str(state / "chunks"),
                       Storage__LocalRoot=str(state / "storage"))
            if config.get('payment_contract_sandbox'):
                # Synthetic receiving account, loopback-only tests, no real transfers.
                env.update(SePay__SecretKey='hutube-qc-loopback-webhook-only-2026',
                           SePay__AccountNumber='0000000000', SePay__BankCode='970423',
                           SePay__PaymentExpiryMinutes='30', SePay__TransactionCodePrefix='QCLOCAL')
            if config.get('google_probe'):
                integration_env=Path(config['integration_env_file']).resolve()
                if integration_env.name!='.env.local':raise ValueError('Expected explicit integration env file')
                for line in integration_env.read_text(encoding='utf-8-sig').splitlines():
                    if not line.lstrip().startswith('#') and '=' in line:
                        key,value=line.split('=',1)
                        if key.strip()=='Google__ClientId':env[key.strip()]=value.strip().strip('"').strip("'")
            if config.get('real_mail_probe'):
                if args.groups not in ('manual-mail','manual-mail-reset') or not args.resume_run:
                    raise ValueError('Real mail mode is restricted to the dedicated recipient-only probe with resumed QC actors')
                # Load only email settings; never copy secrets into runtime config or reports.
                for line in (REPO/'.env.local').read_text(encoding='utf-8-sig').splitlines():
                    if not line.lstrip().startswith('#') and '=' in line:
                        key,value=line.split('=',1)
                        if key.strip().startswith('Email__'):env[key.strip()]=value.strip().strip('"').strip("'")
                if env.get('Email__Mode') not in ('Smtp','GmailApi'):raise ValueError('A real mail transport is required')
            if config.get('recommendation_sandbox'):
                sandbox=ROOT/'.state/recommendation-sandbox'
                python=sandbox/'.venv/Scripts/python.exe'
                if not python.exists():raise RuntimeError('Install isolated recommendation sandbox dependencies first')
                for port in (53492,53493):assert_port_available(port)
                # Only loopback endpoints and disposable synthetic credentials. No real R2 bucket.
                s3=server([str(python),'-m','moto.server','-H','127.0.0.1','-p','53492'],'s3-emulator.log')
                wait_health('http://127.0.0.1:53492/',s3,60)
                checked([str(python),str(ROOT/'support/recommendation_sandbox.py')], 's3-bootstrap.log')
                reco_env=dict(os.environ)
                reco_env.update(R2_ACCOUNT_ID='qc',R2_ACCESS_KEY_ID='hutube-qc-only',R2_SECRET_ACCESS_KEY='hutube-qc-only-secret',
                    R2_BUCKET_NAME='hutube-qc-recommendations',R2_ENDPOINT_URL='http://127.0.0.1:53492',
                    RECOMMENDER_ADMIN_TOKEN='hutube-qc-model-admin',RECOMMENDER_SERVICE_TOKEN='hutube-qc-model-service',
                    MODEL_STORAGE_PATH=str(run/'trained-models'),ALLOW_BENCHMARK_MODEL='false',APP_ENV='test')
                reco=server([str(python),'-m','uvicorn','app.main:app','--host','127.0.0.1','--port','53493'],
                    'recommendation-service.log',REPO/'recommendation-service',reco_env)
                wait_health('http://127.0.0.1:53493/health',reco,120)
                env.update(Recommendation__Storage__AccountId='qc',Recommendation__Storage__AccessKeyId='hutube-qc-only',
                    Recommendation__Storage__SecretAccessKey='hutube-qc-only-secret',Recommendation__Storage__BucketName='hutube-qc-recommendations',
                    Recommendation__Storage__EndpointUrl='http://127.0.0.1:53492',Recommendation__Enabled='true',
                    Recommendation__ServiceUrl='http://127.0.0.1:53493',Recommendation__AdminToken='hutube-qc-model-admin',
                    Recommendation__ServiceToken='hutube-qc-model-service')
                config['recommendation_storage_kind']='Loopback Moto S3 emulator; actual training/service; not Cloudflare R2 certification'
                if config.get('model_transport_proxy'):
                    assert_port_available(53494)
                    config['model_transport_root']=str(run/'model-transport')
                    model_proxy=server([sys.executable,str(ROOT/'support/model_transport_proxy.py'),'--port','53494','--control-root',config['model_transport_root']], 'model-transport-proxy.log')
                    wait_health('http://127.0.0.1:53494/health',model_proxy,30)
                    env['Recommendation__ServiceUrl']='http://127.0.0.1:53494'
                atomic_json(runtime,config)
            if args.suite in ("web","full","rbac"):
                # The functional Web suite deliberately reloads many pages and uses
                # several synthetic actors behind the same loopback IP. Keep the
                # resource rate-limit behavior covered by backend integration tests
                # instead of making unrelated UI cases compete for one local bucket.
                for policy in (
                    "Auth",
                    "Feed",
                    "Search",
                    "Playback",
                    "Upload",
                    "UploadPreflight",
                    "UploadChunk",
                    "PaymentInitiate",
                    "PaymentWebhook",
                    "Admin",
                    "Moderation",
                    "CfSeeder",
                    "CfSeederUpload",
                    "RecommendationJob",
                ):
                    env[f"RateLimit__{policy}PermitLimit"] = "10000"
                env["RateLimit__RecommendationJobConcurrencyLimit"] = "1000"
                env["RateLimit__RecommendationJobQueueLimit"] = "1000"
            api_project = REPO / "backend/src/HuTube.Api"
            dll = api_project / "bin/Debug/net10.0/HuTube.Api.dll"
            api_content_root=api_project
            if args.suite=='full':
                api_content_root=state/'api-root'
                api_content_root.mkdir(exist_ok=True)
                shutil.copy2(api_project/'appsettings.json',api_content_root/'appsettings.json')
                env['GeoIp__Enabled']='false'
                config['mail_dir']=str(state/'mail')
                atomic_json(runtime,config)
            if not args.reuse_build:
                checked(["dotnet", "build", str(api_project)], "backend-build.log")
                for app in ("user", "admin"):
                    command = ["cmd.exe", "/d", "/c", "npm", "run", "build"] if os.name == "nt" else ["npm", "run", "build"]
                    checked(command, f"{app}-build.log", REPO / f"frontend/{app}-web")
            if not dll.exists():
                raise RuntimeError("Build API first, or remove --reuse-build.")
            checked(["dotnet", str(dll), "--migrate"], "migrate.log", api_content_root, env)
            api_origin = config["api_url"].removesuffix("/api/v1")
            api = server(["dotnet", str(dll), "--urls", api_origin], "api.log", api_content_root, env)
            wait_health(api_origin + "/health", api, config["startup_seconds"])
            event('api-ready')
            # Exact endpoint inventory for the backend test plan, without JWT or data responses.
            with urlopen(api_origin + "/openapi/v1.json", timeout=30) as response:
                atomic_json(run / "openapi.json", json.load(response))
            browser_api_url=config['api_url']
            if config.get('transport_proxy_port'):
                proxy_port=int(config['transport_proxy_port'])
                assert proxy_port in (53482,53483)
                assert_port_available(proxy_port)
                config['transport_fault_file']=str(run/'upload-transport-fault.arm')
                proxy=server([sys.executable,str(ROOT/'support/transport_proxy.py'),'--port',str(proxy_port),
                    '--target',api_origin,'--control',config['transport_fault_file']], 'transport-proxy.log')
                browser_api_url='http://127.0.0.1:'+str(proxy_port)+'/api/v1'
                wait_health('http://127.0.0.1:'+str(proxy_port)+'/health',proxy,config['startup_seconds'])
                atomic_json(runtime,config)
            for app in ("user", "admin"):
                web_root = REPO / f"frontend/{app}-web/dist/{app}-web/browser"
                if not (web_root / "index.html").exists():
                    raise RuntimeError(f"Missing {app} Angular build.")
                web = server([sys.executable, str(ROOT / "support/serve.py"), "--root", str(web_root), "--port", str(urlsplit(config[app + '_url']).port), "--api-url", browser_api_url, "--user-url", config["user_url"]], f"{app}-server.log")
                wait_health(config[app + "_url"] + "/login", web, config["startup_seconds"])
                event(app + '-spa-ready')
            script = ROOT / ("tests/auth.py" if args.suite == "auth" else "tests/rbac_matrix.py" if args.suite == "rbac" else "tests/full_functional.py" if args.suite=="full" else "tests/web_all.py")
            child_args=[sys.executable,"-u",str(script),"--config",str(runtime)]
            if args.suite=="full":child_args+=['--groups',args.groups]
            if args.suite=="full" and args.delta_only:child_args+=['--delta-only']
            if args.suite=="full" and args.resume_run:child_args+=['--resume-run',args.resume_run]
            if args.suite=="full" and args.headed:child_args+=['--headed']
            if config.get('runtime_control'):
                config['runtime_control_request']=str(run/'runtime-control.request.json')
                config['runtime_control_response']=str(run/'runtime-control.response.json')
                atomic_json(runtime,config)
            child = server(child_args, args.suite + ".log", ROOT, {**os.environ, "PYTHONIOENCODING": "utf-8"})
            try:
                deadline=time.monotonic()+(config['suite_seconds'] if args.suite=='auth' else max(28800 if args.suite=='full' else 1200,config['suite_seconds']))
                while True:
                    if config.get('runtime_control'):
                        from support.runtime_control import handle as control_owned_runtime
                        api=control_owned_runtime(config,run,api,dll,api_origin,api_content_root,env,server,stop_process,wait_health)
                    try:
                        code=child.wait(timeout=0.5)
                        break
                    except subprocess.TimeoutExpired:
                        if time.monotonic()>deadline:raise
            except subprocess.TimeoutExpired:
                stop_process(child)
                raise TimeoutError(f"{args.suite} suite exceeded its wall-clock budget; state is retained for recovery.") from None
            print(f"Artifacts: {run}", flush=True)
            event('suite-exit', exit_code=code)
            if code:
                raise RuntimeError(f"{args.suite} cases failed; inspect report.json, screenshots and {args.suite}.log.")
            report = json.loads((run / "report.json").read_text(encoding="utf-8"))
            print(f"PASS: {report['passed']} cases; {report.get('reused', 0)} prerequisites reused; account_count={report.get('account_count', 'n/a')}", flush=True)
        except Exception as error:
            event('runner-error', error_type=type(error).__name__)
            if args.suite in ('web','full','rbac'):
                report_path = run / 'report.json'
                report = json.loads(report_path.read_text(encoding='utf-8')) if report_path.exists() else {
                    'suite': 'rbac' if args.suite == 'rbac' else 'web', 'run_id': run.name, 'cases': [], 'page_errors': [],
                    'setup': [{'status': 'failed', 'phase': 'runner', 'error_type': type(error).__name__}]}
                for status in ('passed', 'failed', 'blocked', 'reused'):
                    report[status] = sum(case['status'] == status for case in report['cases'])
                if not report.get('finished_at') or not report['cases'] or not (report['failed'] or report['blocked']):
                    report['run_error'] = report.get('run_error') or type(error).__name__
                atomic_json(report_path, report)
                for application in ('user', 'admin'):
                    atomic_json(run / (application + '-report.json'), {
                        'suite': application + '-web', 'run_id': run.name,
                        'cases': [case for case in report['cases'] if case['application'] == application]})
                latest = 'rbac-latest.json' if args.suite == 'rbac' else 'web-latest.json'
                atomic_json(ROOT / 'artifacts' / latest, {'run_dir': str(run),
                    **{key: report[key] for key in ('passed', 'failed', 'blocked', 'reused')},
                    'run_error': report.get('run_error')})
            raise
        finally:
            for process in reversed(programs):
                stop_process(process)
            for handle in handles:
                handle.close()
            if pg_started:
                # A fast shutdown still flushes the database. Windows disks can
                # need longer than 30s after media/E2E writes; keep a finite budget.
                stop_seconds = max(30, min(300, int(config.get("postgres_shutdown_seconds", 120))))
                checked([executable("pg_ctl"), "-D", str(pg_root), "-m", "fast", "-w", "-t", str(stop_seconds), "stop"],
                        "postgres-stop.log", timeout=stop_seconds + 10)


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        print(f"FAIL: {exc}", file=sys.stderr)
        sys.exit(1)
