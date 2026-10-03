"""Serve a built Angular SPA without changing its generated config.json."""
import argparse
import json
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlsplit


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", required=True)
    parser.add_argument("--port", type=int, required=True)
    parser.add_argument("--api-url", required=True)
    parser.add_argument("--user-url", required=True)
    args = parser.parse_args()
    root = Path(args.root).resolve()

    class Handler(SimpleHTTPRequestHandler):
        def __init__(self, *a, **kw):
            super().__init__(*a, directory=str(root), **kw)

        def do_GET(self):
            pathname = urlsplit(self.path).path
            if pathname.endswith("/config.json"):
                payload = json.dumps({"API_BASE_URL": args.api_url, "USER_WEB_BASE_URL": args.user_url}).encode()
                self.send_response(200); self.send_header("Content-Type", "application/json")
                self.send_header("Cache-Control", "no-store"); self.send_header("Content-Length", str(len(payload)))
                self.end_headers(); self.wfile.write(payload); return
            if not Path(self.translate_path(pathname)).is_file() and "." not in pathname.rsplit("/", 1)[-1]:
                self.path = "/index.html"
            super().do_GET()

        def log_message(self, *args):
            pass

    ThreadingHTTPServer(("127.0.0.1", args.port), Handler).serve_forever()


if __name__ == "__main__":
    main()
