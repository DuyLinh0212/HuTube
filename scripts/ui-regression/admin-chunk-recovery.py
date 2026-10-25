"""Exercise real lazy imports, bounded document recovery and offline-safe retry."""
import argparse
from contextlib import contextmanager
from datetime import datetime, timedelta, timezone
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
import json
from pathlib import Path
import re
from threading import Thread
from urllib.parse import urlsplit, unquote

from playwright.sync_api import expect, sync_playwright


@contextmanager
def serve(root):
    class Handler(SimpleHTTPRequestHandler):
        def log_message(self, *_args):
            pass

        def do_GET(self):
            path = unquote(urlsplit(self.path).path)
            target = (root / path.lstrip('/')).resolve()
            if not target.is_relative_to(root):
                self.send_error(403)
                return
            if not target.is_file() and '.' in Path(path).name:
                self.send_error(404)
                return
            if not target.is_file():
                self.path = '/index.html'
            return super().do_GET()

        def end_headers(self):
            self.send_header('Cache-Control', 'no-store')
            super().end_headers()

    server = ThreadingHTTPServer(('127.0.0.1', 0), partial(Handler, directory=str(root)))
    thread = Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        yield 'http://127.0.0.1:' + str(server.server_port)
    finally:
        server.shutdown()
        server.server_close()
        thread.join(timeout=5)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, required=True)
    parser.add_argument('--artifacts', type=Path, required=True)
    parser.add_argument('--browser-path')
    args = parser.parse_args()
    root = args.root.resolve()
    args.artifacts.mkdir(parents=True, exist_ok=True)
    # Support both development and production Angular output names.
    chunks = [file for file in root.glob('*.js') if 'app-admin-moderation-page' in file.read_text(encoding='utf-8')]
    assert len(chunks) == 1, 'Expected one moderation lazy module'
    chunk = chunks[0].name
    user = dict(userId='isolated-admin', username='reviewer', displayName='Reviewer', email='reviewer@example.test',
                isAdmin=True, emailVerified=True, role='admin', permissions=['role.view', 'moderation.view_queue', 'policy.view'])
    errors, results = [], []

    def api(route):
        request = route.request
        path = urlsplit(request.url).path.split('/api/v1')[-1]
        headers = {'Access-Control-Allow-Origin': request.headers.get('origin', '*'),
                   'Access-Control-Allow-Credentials': 'true', 'Access-Control-Allow-Methods': 'GET,POST,OPTIONS',
                   'Access-Control-Allow-Headers': request.headers.get('access-control-request-headers', '*')}
        if request.method == 'OPTIONS':
            route.fulfill(status=204, headers=headers)
            return
        data = dict(items=[], total=0, page=1, pageSize=100)
        if path == '/auth/refresh':
            data = dict(accessToken='isolated-chunk-test', expiresAt=(datetime.now(timezone.utc) + timedelta(hours=1)).isoformat(), user=user)
        elif path in ['/auth/me', '/admin/me']:
            data = user
        elif path in ['/admin/roles', '/admin/permissions', '/policies', '/admin/moderation/queue']:
            data = []
        route.fulfill(status=200, headers=headers, content_type='application/json', body=json.dumps(data))

    with serve(root) as base, sync_playwright() as playwright:
        browser = playwright.chromium.launch(headless=True, executable_path=args.browser_path)
        for mode in ['once', 'persistent', 'storage-blocked']:
            context = browser.new_context(viewport={'width': 440 if mode == 'storage-blocked' else 1440, 'height': 956}, color_scheme='dark' if mode == 'storage-blocked' else 'light')
            context.route('**/api/v1/**', api)
            context.add_init_script("localStorage.setItem('hutube_lang', '" + ('en' if mode == 'storage-blocked' else 'vi') + "')")
            if mode == 'storage-blocked':
                context.add_init_script("Object.defineProperty(window, 'sessionStorage', {get() {throw new Error('disabled')}})")
            failures = {'count': 0, 'enabled': True}

            def intercept(route):
                failures['count'] += 1
                if failures['enabled'] and (mode != 'once' or failures['count'] == 1):
                    route.fulfill(status=200, content_type='text/html', headers={'Cache-Control': 'no-store'}, body='<!doctype html><title>Stale deployment fallback</title>')
                else:
                    route.continue_()

            context.route('**/' + chunk, intercept)
            page = context.new_page()
            page.on('pageerror', lambda error: errors.append(str(error)))
            documents = []
            page.on('request', lambda request: documents.append(request.url) if request.is_navigation_request() and request.frame == page.main_frame else None)
            page.goto(base + '/roles')
            page.wait_for_load_state('networkidle')
            link = page.locator('a[href="/moderation/videos"]').first
            if mode == 'storage-blocked':
                # The narrow shell hides its links behind the standard menu.
                page.locator('.topbar .menu-button').click()
            link.click()
            if mode == 'once':
                expect(page.locator('app-admin-moderation-page')).to_be_visible(timeout=20000)
                expect(page).to_have_url(base + '/moderation/videos')
                assert failures['count'] == 2
                assert len(documents) == 2, documents
            else:
                expect(page.locator('app-page-load-error')).to_be_visible(timeout=20000)
                expect(page).to_have_url(re.compile('/load-error\\?returnUrl='))
                expect(page.get_by_role('heading', level=1)).to_have_text('Unable to open this page' if mode == 'storage-blocked' else 'Chưa thể mở trang')
                page.wait_for_timeout(1800)
                assert len(documents) == (1 if mode == 'storage-blocked' else 2), documents
                failures['enabled'] = False
                page.screenshot(path=str(args.artifacts / (mode + '.png')), full_page=True)
                page.get_by_role('button', name='Retry' if mode == 'storage-blocked' else 'Thử lại', exact=True).click()
                expect(page.locator('app-admin-moderation-page')).to_be_visible(timeout=20000)
            results.append({'scenario': mode, 'lazy_requests': failures['count'], 'documents': len(documents), 'passed': True})
            expect(page.locator('app-admin-moderation-page [role="alert"]')).to_have_count(0)
            page.screenshot(path=str(args.artifacts / (mode + '-restored.png')), full_page=True)
            context.close()
        browser.close()
    assert not errors, errors
    (args.artifacts / 'result.json').write_text(json.dumps({'results': results, 'page_errors': errors}, indent=2), encoding='utf-8')
    print(json.dumps(results))


if __name__ == '__main__':
    main()
