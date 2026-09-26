"""
Script khởi động Bot Simulator Web Dashboard cho HuTube
Mặc định chạy tại http://localhost:5050
"""

import argparse
import sys
import uvicorn

# Đảm bảo UTF-8 trên Windows console
if sys.platform == "win32":
    try:
        sys.stdout.reconfigure(encoding="utf-8")
        sys.stderr.reconfigure(encoding="utf-8")
    except Exception:
        pass

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="HuTube Bot Simulator & Interaction Seeder")
    parser.add_argument("--host", default="0.0.0.0", help="Host lắng nghe (mặc định: 0.0.0.0)")
    parser.add_argument("--port", type=int, default=5050, help="Cổng chạy Web UI (mặc định: 5050)")
    parser.add_argument("--backend", default="http://localhost:5080/api/v1", help="URL HuTube Backend API")
    args = parser.parse_args()

    from web_app import app, engine
    engine.base_url = args.backend.rstrip("/")

    print("=" * 65)
    print(f"  [+] HuTube Bot Simulator & Interaction Seeder Web Dashboard")
    print(f"  [+] URL Giao Dien Web: http://localhost:{args.port}")
    print(f"  [+] Ket Noi Backend API: {engine.base_url}")
    print("=" * 65)
    print("  Nhan Ctrl+C de dung server.\n")

    uvicorn.run(app, host=args.host, port=args.port, log_level="info")
