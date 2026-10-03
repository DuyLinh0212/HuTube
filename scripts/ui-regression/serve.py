from http.server import ThreadingHTTPServer, SimpleHTTPRequestHandler
from pathlib import Path
import argparse
parser = argparse.ArgumentParser()
parser.add_argument('--root', required=True)
parser.add_argument('--port', type=int, required=True)
args = parser.parse_args()
root = Path(args.root).resolve()
class Handler(SimpleHTTPRequestHandler):
    def __init__(self, *a, **kw): super().__init__(*a, directory=str(root), **kw)
    def do_GET(self):
        if not Path(self.translate_path(self.path)).is_file() and '.' not in self.path.split('?')[0].split('/')[-1]:
            self.path = '/index.html'
        super().do_GET()
    def log_message(self, *args): pass
ThreadingHTTPServer(('127.0.0.1', args.port), Handler).serve_forever()
