"""Check channel suspension duration against local Admin Web and isolated API fixtures."""
import argparse
import json
from datetime import datetime, timedelta, timezone
from pathlib import Path
from urllib.parse import urlparse

from playwright.sync_api import expect, sync_playwright


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--url', default='http://127.0.0.1:4308')
    parser.add_argument('--browser-path')
    parser.add_argument('--artifacts', required=True, type=Path)
    args = parser.parse_args()
    args.artifacts.mkdir(parents=True, exist_ok=True)
    date = datetime.now(timezone.utc).isoformat()
    channel = dict(channelId='11111111-1111-4111-8111-111111111111', name='Wolf Music', handle='wolfmusic',
                   ownerUserId='owner', ownerName='Owner', ownerEmail='owner@example.test',
                   status='active', statusReason=None, suspendedUntil=None, createdAt=date,
                   videoCount=2, subscriberCount=0, activeStrikeCount=0, viewCount=1)
    user = dict(userId='admin', username='admin', displayName='Administrator', email='admin@example.test',
                emailVerified=True, isAdmin=True, role='super_admin',
                permissions=['channel.view', 'channel.suspend', 'channel.ban', 'channel.unban', 'channel.delete'])
    posts, errors = [], []
    fail_once = True

    def api(route):
        nonlocal fail_once
        request = route.request
        headers = {'Access-Control-Allow-Origin': request.headers.get('origin', args.url),
                   'Access-Control-Allow-Credentials': 'true',
                   'Access-Control-Allow-Headers': request.headers.get('access-control-request-headers', '*'),
                   'Access-Control-Allow-Methods': 'GET,POST,PUT,PATCH,DELETE,OPTIONS'}

        def respond(data, status=200):
            route.fulfill(status=status, headers=headers, content_type='application/json', body=json.dumps(data))

        if request.method == 'OPTIONS':
            route.fulfill(status=204, headers=headers)
            return
        path = urlparse(request.url).path.split('/api/v1', 1)[-1]
        data = dict(items=[], page=1, pageSize=8, total=0)
        if path == '/auth/refresh':
            data = dict(accessToken='isolated-test', expiresAt=(datetime.now(timezone.utc) + timedelta(hours=1)).isoformat(), user=user)
        elif path in ['/auth/me', '/admin/me']:
            data = user
        elif path == '/admin/channels/counts':
            data = dict(all=1, active=int(channel['status'] == 'active'), restricted=int(channel['status'] == 'suspended'), banned=0)
        elif path == '/admin/channels':
            data = dict(items=[channel], page=1, pageSize=8, total=1)
        elif path.endswith('/suspend') or path.endswith('/unban'):
            body = request.post_data_json
            posts.append(dict(action=path.rsplit('/', 1)[-1], **body))
            if fail_once:
                fail_once = False
                respond(dict(message='Thử lại thao tác'), 503)
                return
            channel.update(status='suspended' if path.endswith('/suspend') else 'active',
                           suspendedUntil=body.get('suspendedUntil'), statusReason=body['reason'])
            route.fulfill(status=204, headers=headers)
            return
        elif path.startswith('/admin/channels/'):
            data = dict(channel=channel, description=None, contactEmail=None, avatarUrl=None,
                        bannerUrl=None, watermarkUrl=None, videos=[], history=[])
        respond(data)

    with sync_playwright() as playwright:
        browser = playwright.chromium.launch(headless=True, executable_path=args.browser_path)
        context = browser.new_context(viewport={'width': 1440, 'height': 1000}, locale='vi-VN', timezone_id='Asia/Bangkok')
        context.route('**/api/v1/**', api)
        context.add_init_script("localStorage.setItem('hutube_lang', localStorage.getItem('hutube_lang') || 'vi')")
        page = context.new_page()
        page.on('pageerror', lambda error: errors.append(str(error)))

        def open_suspension(label='Tạm ngưng kênh'):
            page.locator('.channel-row').click()
            page.locator('.drawer-actions').get_by_role('button', name=label, exact=True).click()
            dialog = page.get_by_role('dialog')
            expect(dialog).to_be_visible()
            expect(dialog.locator('select')).to_have_value('7')
            return dialog

        page.goto(args.url + '/channels')
        page.wait_for_load_state('networkidle')
        dialog = open_suspension()
        duration = dialog.get_by_label('Thời gian tạm ngưng', exact=True)
        expect(duration).to_be_focused()
        expect(duration.locator('option')).to_have_count(6)
        dialog.locator('textarea').fill('Tạm ngưng theo thời hạn')
        duration.select_option('custom')
        custom = dialog.locator('input[type=datetime-local]')
        confirm = dialog.locator('.confirm-submit')
        expect(confirm).to_be_disabled()
        custom.fill('2000-01-01T10:00')
        expect(confirm).to_be_disabled()
        future = (datetime.now(timezone(timedelta(hours=7))) + timedelta(days=3)).replace(second=0, microsecond=0)
        local_date = future.strftime('%Y-%m-%dT%H:%M')
        custom.fill(local_date)
        expect(confirm).to_be_enabled()
        expect(dialog.locator('input[type=checkbox]')).to_be_checked()
        page.screenshot(path=str(args.artifacts / 'suspension-custom-desktop.png'))
        confirm.click()
        expect(dialog).to_contain_text('Thử lại thao tác')
        expect(custom).to_have_value(local_date)
        confirm.click()
        expect(page.get_by_role('dialog')).to_have_count(0)
        expect(page.locator('.suspension-summary')).to_contain_text('Tạm ngưng đến')
        assert posts[0] == posts[1]
        assert datetime.fromisoformat(posts[1]['suspendedUntil'].replace('Z', '+00:00')) == future
        assert posts[1]['notifyOwner'] is True

        page.locator('.drawer-actions .btn-action-green').click()
        dialog = page.get_by_role('dialog')
        expect(dialog.locator('select')).to_have_count(0)
        dialog.locator('textarea').fill('Mở lại trước hạn')
        dialog.locator('.confirm-submit').click()
        expect(page.get_by_role('dialog')).to_have_count(0)
        expect(page.locator('.suspension-summary')).to_have_count(0)
        assert 'suspendedUntil' not in posts[-1]

        page.set_viewport_size({'width': 375, 'height': 900})
        page.evaluate("localStorage.setItem('hutube_theme', 'dark'); localStorage.setItem('hutube_admin_theme', 'dark')")
        page.reload()
        page.wait_for_load_state('networkidle')
        dialog = open_suspension()
        dialog.locator('select').select_option('custom')
        dialog.locator('input[type=datetime-local]').fill(local_date)
        page.screenshot(path=str(args.artifacts / 'suspension-custom-narrow-dark.png'))
        for box in dialog.locator('select, input[type=datetime-local], textarea, .confirm-submit').all():
            rect = box.bounding_box()
            assert rect['x'] >= 0 and rect['x'] + rect['width'] <= 375, rect
        dialog.locator('.confirm-cancel').click()

        page.evaluate("localStorage.setItem('hutube_lang', 'en'); localStorage.setItem('hutube_admin_lang', 'en')")
        page.reload()
        page.wait_for_load_state('networkidle')
        dialog = open_suspension('Suspend channel')
        expect(dialog.get_by_label('Suspension duration', exact=True)).to_be_visible()
        dialog.locator('select').select_option('indefinite')
        expect(dialog.locator('input[type=datetime-local]')).to_have_count(0)
        dialog.locator('textarea').fill('Manual restore required')
        dialog.locator('.confirm-submit').click()
        expect(page.get_by_role('dialog')).to_have_count(0)
        expect(page.locator('.suspension-summary')).to_contain_text('Until an administrator restores the channel')
        assert posts[-1]['suspendedUntil'] is None
        assert not errors, errors
        browser.close()
    (args.artifacts / 'result.json').write_text(json.dumps(dict(status='passed', posts=posts, errors=errors), indent=2), encoding='utf-8')
    print('PASS: duration presets, custom date validation/UTC, failure retry, refreshed expiry, early restore, narrow/dark layout and English indefinite suspension')


if __name__ == '__main__':
    main()
