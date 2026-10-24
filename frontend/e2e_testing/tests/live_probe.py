"""Read-only reconnaissance of the explicitly requested running Web apps."""
import json
import os
from pathlib import Path
from urllib.parse import urlsplit
from playwright.sync_api import sync_playwright, expect

ROOT = Path(__file__).resolve().parents[1]

def main():
    credentials = json.loads(os.environ['WEB_E2E_CREDENTIALS'])
    destination = ROOT / 'artifacts/live-probe'
    destination.mkdir(parents=True, exist_ok=True)
    with sync_playwright() as pw:
        browser = pw.chromium.launch(headless=True, executable_path=os.environ.get('CHROME_BIN') or r'C:\Program Files\Google\Chrome\Application\chrome.exe')
        for app, routes in [('user', ['/account','/playlists','/explore','/liked','/studio/content','/studio/settings','/plans']), ('admin', ['/account','/videos','/users','/channels','/roles','/moderation/reports','/moderation/appeals','/moderation/strikes','/recommendations'])]:
            context = browser.new_context(viewport={'width':1440,'height':960}, locale='vi-VN')
            page = context.new_page()
            page.set_default_timeout(15000)
            page.set_default_navigation_timeout(45000)
            origin = 'http://localhost:' + ('4200' if app == 'user' else '4201')
            page.goto(origin + '/login')
            page.locator('#email').fill(credentials[app]['email'])
            page.locator('#password').fill(credentials[app]['password'])
            with page.expect_response(lambda r: r.request.method == 'POST' and urlsplit(r.url).path == '/api/v1/auth/login', timeout=30000) as pending:
                page.locator('button[type=submit]').click()
            print(app, 'login', pending.value.status, flush=True)
            assert pending.value.status == 200
            identity = pending.value.json()['user']
            print(app, 'role', identity.get('roleCode'), identity.get('isAdmin'), identity.get('isSuperAdmin'), flush=True)
            page.wait_for_url('**/' + ('home' if app == 'user' else 'account'))
            for route in routes:
                page.goto(origin + route)
                selector = {'/account':'app-account-page','/playlists':'app-playlists-page','/explore':'app-explore-page','/liked':'app-library-page','/studio/content':'app-studio-content-page','/studio/settings':'app-studio-settings-page','/plans':'app-plans-page','/videos':'app-admin-videos-page','/users':'app-admin-users-page','/channels':'app-admin-channels-page','/roles':'app-admin-rbac-page','/moderation/reports':'app-admin-reports-page','/moderation/appeals':'app-admin-appeals-page','/moderation/strikes':'app-admin-strikes-page','/recommendations':'app-recommendations-page'}[route]
                try:
                    page.locator(selector).wait_for(timeout=20000)
                except Exception:
                    print(app, route, 'unavailable at', urlsplit(page.url).path, flush=True)
                # Wait on concrete loaders, never networkidle on realtime pages.
                page.locator('.table-loading-overlay,.drawer-loading,.loading-state').first.wait_for(state='hidden',timeout=15000)
                name = app + route.replace('/','-')
                page.screenshot(path=str(destination/(name+'.png')), full_page=True)
                info = page.evaluate('''() => ({url:location.pathname,text:document.body.innerText, inputs:[...document.querySelectorAll('input,select,textarea')].map(e=>({tag:e.tagName,type:e.type,id:e.id,name:e.name,placeholder:e.placeholder,options:e.tagName==='SELECT'?[...e.options].map(o=>({text:o.text,value:o.value})):undefined})), buttons:[...document.querySelectorAll('button')].map(e=>({text:e.innerText,title:e.title,aria:e.getAttribute('aria-label'),class:e.className,disabled:e.disabled}))})''')
                (destination/(name+'.json')).write_text(json.dumps(info,ensure_ascii=False,indent=2),encoding='utf-8')
                print(name, info['url'], len(info['buttons']), 'buttons', flush=True)
            context.close()
        browser.close()

if __name__ == '__main__':
    main()
