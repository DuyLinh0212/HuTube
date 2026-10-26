"""Check the account drawer with zero, one, and 100 collaboration channels."""
import argparse
from datetime import datetime, timedelta, timezone
import json
import re
from pathlib import Path
from urllib.parse import urlparse
from playwright.sync_api import expect, sync_playwright


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--base-url', default='http://127.0.0.1:4393')
    parser.add_argument('--artifacts', type=Path, required=True)
    parser.add_argument('--browser-path')
    args = parser.parse_args()
    args.artifacts.mkdir(parents=True, exist_ok=True)
    user = {'userId': 'viewer', 'username': 'viewer', 'email': 'viewer@example.test',
            'displayName': 'Duy Linh Nguyễn', 'isAdmin': False, 'emailVerified': True}
    owner = {'channelId': 'owner', 'name': 'FanLiverpool', 'handle': 'lynwa', 'isOwner': True,
             'myRole': 'owner', 'permissions': [], 'settings': '{}', 'avatarUrl': None}
    count = 100
    theme = 'light'
    expires = (datetime.now(timezone.utc) + timedelta(hours=2)).isoformat()

    def dispatch(route):
        url = route.request.url
        if '/api/v1/' not in url:
            if url.startswith(args.base_url): route.continue_()
            else: route.abort()
            return
        headers = {'Access-Control-Allow-Origin': args.base_url, 'Access-Control-Allow-Credentials': 'true',
                   'Access-Control-Allow-Headers': '*', 'Access-Control-Allow-Methods': 'GET,POST,OPTIONS'}
        if route.request.method == 'OPTIONS':
            route.fulfill(status=204, headers=headers)
            return
        path = urlparse(url).path.split('/api/v1', 1)[1]
        data = {'items': [], 'total': 0}
        if path == '/auth/refresh': data = {'accessToken': 'isolated-fixture', 'expiresAt': expires, 'user': user}
        elif path == '/auth/me': data = user
        elif path == '/account/profile': data = {**user, 'avatarUrl': None}
        elif path == '/account/settings': data = {'language': 'vi', 'theme': theme}
        elif path == '/channels/me': data = owner
        elif path == '/channels/accessible':
            data = [owner, *[{**owner, 'channelId': f'collab-{i}', 'name': f'Kênh cộng tác {i}',
                'handle': f'kenh{i}', 'isOwner': False, 'myRole': 'moderator'} for i in range(1, count + 1)]]
        elif any(part in path for part in ['/invitations', '/subscribed', '/subscriptions', '/categories', '/playlists']): data = []
        elif path == '/plans/my-plan': data = {'features': {}, 'subscription': None}
        elif path.endswith('/negotiate'): data = {'negotiateVersion': 1, 'connectionId': 'fixture', 'connectionToken': 'fixture', 'availableTransports': []}
        route.fulfill(headers=headers, content_type='application/json', body=json.dumps(data))

    results = []
    with sync_playwright() as p:
        browser = p.chromium.launch(headless=True, **({'executable_path': args.browser_path} if args.browser_path else {}))
        context = browser.new_context(locale='vi-VN', reduced_motion='reduce')
        context.route('**/*', dispatch)
        context.add_init_script("localStorage.setItem('hutube_lang','vi'); localStorage.setItem('hutube_theme','light');")
        page = context.new_page()
        errors = []
        page.on('pageerror', lambda error: errors.append(str(error)))
        for width in [320, 440, 1280]:
            for count in [0, 1, 100]:
                page.set_viewport_size({'width': width, 'height': 956})
                page.goto(args.base_url + '/playlists')
                page.wait_for_load_state('networkidle')
                page.locator('.top-avatar').click()
                drawer = page.locator('#account-drawer')
                expect(drawer).to_be_visible()
                expect(drawer).to_have_class(re.compile('account-drawer--ready'))
                block = page.locator('[aria-labelledby="drawer-collaboration-title"]')
                if count == 0:
                    expect(block).to_have_count(0)
                elif count == 1:
                    expect(block.locator('a.drawer-channel-link')).to_have_count(1)
                    expect(block.locator('a')).to_have_attribute('href', '/studio/overview?channelId=collab-1')
                    expect(block.locator('.drawer-channel-selector')).to_have_count(0)
                else:
                    expect(block.locator('.drawer-channel-link:visible')).to_have_count(1)
                    before = drawer.locator('.account-drawer__body').evaluate('(el) => el.scrollHeight')
                    trigger = block.locator('.drawer-channel-selector')
                    expect(trigger.locator('.drawer-channel-count')).to_have_text('100')
                    trigger.click()
                    picker = page.locator('#collaboration-channel-picker')
                    expect(picker).to_be_visible()
                    expect(trigger).to_have_attribute('aria-expanded', 'true')
                    expect(picker.locator('a')).to_have_count(100)
                    box = picker.bounding_box()
                    assert box and box['height'] <= 351 and box['x'] >= 0 and box['x'] + box['width'] <= width + 1, box
                    assert drawer.locator('.account-drawer__body').evaluate('(el) => el.scrollHeight') == before
                    assert picker.locator('nav').evaluate('(el) => el.scrollHeight > el.clientHeight')
                    picker.locator('nav').evaluate('(el) => el.scrollTop = el.scrollHeight')
                    expect(picker).to_be_visible()
                    search = picker.locator('input')
                    search.fill('@kenh100')
                    expect(picker.locator('a')).to_have_count(1)
                    expect(picker.locator('a')).to_have_attribute('href', '/studio/overview?channelId=collab-100')
                    search.fill('không tồn tại')
                    expect(picker.get_by_role('status')).to_have_text('Không tìm thấy kênh')
                    page.keyboard.press('Escape')
                    expect(picker).not_to_be_visible()
                    expect(drawer).to_be_visible()
                    trigger.click()
                    expect(search).to_have_value('')
                    page.screenshot(path=str(args.artifacts / f'picker-{width}.png'))
                    page.set_viewport_size({'width': width, 'height': 600})
                    expect(picker).to_be_visible()
                    expect(search).to_be_focused()
                    page.wait_for_function("() => { const r = document.querySelector('#collaboration-channel-picker').getBoundingClientRect(); return r.y >= 0 && r.bottom <= innerHeight; }")
                    page.keyboard.press('Escape')
                page.keyboard.press('Escape')
                expect(drawer).to_have_count(0)
                results.append({'width': width, 'channels': count, 'passed': True})
        assert not errors, errors
        (args.artifacts / 'results.json').write_text(json.dumps({'scenarios': results, 'page_errors': errors}, indent=2), encoding='utf-8')
        print(json.dumps({'scenarios': results, 'page_errors': errors}))
        browser.close()


if __name__ == '__main__': main()
