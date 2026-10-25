"""Verify plan allocation visibility and the per-person storage bar using isolated API fixtures."""
import argparse
import copy
import json
from datetime import datetime, timedelta, timezone
from pathlib import Path
from urllib.parse import urlparse

from playwright.sync_api import expect, sync_playwright


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--url', default='http://127.0.0.1:4307')
    parser.add_argument('--browser-path')
    parser.add_argument('--artifacts', type=Path, required=True)
    args = parser.parse_args()
    args.artifacts.mkdir(parents=True, exist_ok=True)
    gb = 1024 ** 3
    date = datetime.now(timezone.utc).isoformat()
    user = dict(userId='owner', displayName='Owner', username='owner', email='owner@example.test',
                emailVerified=True, isAdmin=False, role='user', permissions=[])

    def member(id, status='accepted'):
        return dict(planMemberId=id, planId='family', ownerUserId='owner', memberEmail=f'{id}@example.test',
                    memberUserId=None if status == 'pending' else id, status=status, invitedAt=date,
                    acceptedAt=date if status == 'accepted' else None, revokedAt=None, allocatedStorage=8 * gb,
                    storageUsed=3 * gb if id == 'alice' else 7 * gb if id == 'bob' else 0)

    family = dict(planId='family', code='family', name='Family', description='Shared plan', status='active',
                  price=99000, durationDays=30, storageLimit=30 * gb, usedStorage=12 * gb, remainingStorage=18 * gb,
                  maxUploadSize=gb, maxVideoDuration=3600, maxVideoQuality='1440p', maxDownloadQuality='1080p',
                  maxMembers=6, features={}, members=[member('alice'), member('bob'), member('zero')],
                  ownerAllocatedStorage=5 * gb, ownerOwnStorageUsed=2 * gb, isSharedMember=False,
                  storageUsageBreakdown=[dict(userId='owner', displayName='Owner', storageUsed=2 * gb, isOwner=True),
                    dict(userId='alice', displayName='An', storageUsed=3 * gb, isOwner=False),
                    dict(userId='bob', displayName='Bình và một tên kênh rất dài để kiểm tra hiển thị', storageUsed=7 * gb, isOwner=False),
                    dict(userId='zero', displayName='Chưa tải video', storageUsed=0, isOwner=False)])
    current = copy.deepcopy(family)
    errors, revokes = [], []

    def api(route):
        nonlocal current
        request = route.request
        path = urlparse(request.url).path.split('/api/v1', 1)[-1]
        headers = {'Access-Control-Allow-Origin': request.headers.get('origin', args.url),
                   'Access-Control-Allow-Credentials': 'true',
                   'Access-Control-Allow-Headers': request.headers.get('access-control-request-headers', '*'),
                   'Access-Control-Allow-Methods': 'GET,POST,PUT,PATCH,DELETE,OPTIONS'}

        def respond(data, status=200):
            route.fulfill(status=status, headers=headers, content_type='application/json', body=json.dumps(data))

        if request.method == 'OPTIONS':
            route.fulfill(status=204, headers=headers)
            return
        data = dict(items=[], page=1, pageSize=20, total=0)
        if path == '/auth/refresh':
            data = dict(accessToken='isolated-storage-test', expiresAt=(datetime.now(timezone.utc) + timedelta(hours=1)).isoformat(), user=user)
        elif path == '/auth/me':
            data = user
        elif path == '/plans':
            data = [{key: value for key, value in family.items() if key not in ['members', 'storageUsageBreakdown']}]
        elif path == '/plans/my-plan':
            data = current
        elif path.startswith('/plans/members/') and request.method == 'DELETE':
            id = path.rsplit('/', 1)[-1]
            revokes.append(id)
            current['members'] = [member for member in current['members'] if member['planMemberId'] != id]
            for usage in current['storageUsageBreakdown']:
                if usage['userId'] == id:
                    usage['isFormerMember'] = True
            route.fulfill(status=204, headers=headers)
            return
        elif path == '/channels/me':
            respond({}, 404)
            return
        elif path in ['/subscriptions', '/categories']:
            data = []
        respond(data)

    with sync_playwright() as playwright:
        browser = playwright.chromium.launch(headless=True, executable_path=args.browser_path)
        context = browser.new_context(viewport={'width': 1440, 'height': 1000}, locale='vi-VN')
        context.route('**/api/v1/**', api)
        config_path = Path(__file__).resolve().parents[2] / 'frontend/user-web/public/config.json'
        config = json.loads(config_path.read_text(encoding='utf-8-sig'))
        config['API_BASE_URL'] = 'http://127.0.0.1:5080/api/v1'
        context.route('**/config.json', lambda route: route.fulfill(json=config))
        context.add_init_script("localStorage.setItem('hutube_lang', localStorage.getItem('hutube_lang') || 'vi')")
        page = context.new_page()
        page.on('pageerror', lambda error: errors.append(str(error)))

        def load(data):
            nonlocal current
            current = copy.deepcopy(data)
            page.goto(args.url + '/plans')
            page.wait_for_load_state('networkidle')
            expect(page.locator('.quota-card')).to_be_visible()

        solo = {**family, 'maxMembers': 1, 'members': [], 'usedStorage': 2 * gb, 'remainingStorage': 28 * gb,
                'storageUsageBreakdown': family['storageUsageBreakdown'][:1]}
        load(solo)
        expect(page.locator('.quota-allocation-bar')).to_have_count(0)
        expect(page.locator('.family-storage-bar')).to_have_count(0)
        page.locator('.quota-card').screenshot(path=str(args.artifacts / 'storage-no-invitations.png'))
        load({**solo, 'maxMembers': 6})
        expect(page.locator('.quota-allocation-bar')).to_have_count(0)
        load({**solo, 'maxMembers': 6, 'members': [member('pending', 'pending')]})
        expect(page.locator('.quota-allocation-bar')).to_be_visible()
        expect(page.locator('.family-storage-bar')).to_have_count(0)

        load(family)
        bar = page.locator('.family-storage-bar')
        expect(bar).to_be_visible()
        expect(bar).to_have_attribute('aria-label', 'Bạn (chủ gói): 2 GB; An: 3 GB; Bình và một tên kênh rất dài để kiểm tra hiển thị: 7 GB; Chưa tải video: 0 MB; Còn trống: 18 GB')
        expect(bar.locator('.storage-segment')).to_have_count(4)
        legend = page.locator('.storage-legend')
        expect(legend.locator('li')).to_have_count(5)
        expect(legend.locator('li').filter(has_text='An')).to_contain_text('3 GB')
        expect(legend.locator('li').filter(has_text='Còn trống')).to_contain_text('18 GB')
        widths = bar.locator('.storage-segment').evaluate_all('(nodes) => nodes.map(n => parseFloat(n.style.width))')
        assert abs(sum(widths) - 100) < 0.001, widths
        page.locator('.quota-card').screenshot(path=str(args.artifacts / 'family-storage-desktop.png'))
        page.set_viewport_size({'width': 375, 'height': 1100})
        page.evaluate("document.documentElement.setAttribute('data-theme', 'dark'); document.body.classList.add('dark-theme')")
        page.locator('.quota-card').screenshot(path=str(args.artifacts / 'family-storage-narrow-dark.png'))
        assert page.evaluate('document.documentElement.scrollWidth <= innerWidth'), 'Horizontal page overflow'
        mini_spec = page.locator('.quota-card .mini-spec').first
        assert mini_spec.evaluate(r'(node) => parseInt(getComputedStyle(node).backgroundColor.match(/\d+/)[0]) < 100'), 'Dark spec surface must stay dark'
        expect(mini_spec.locator('.ms-val')).to_be_visible()
        assert mini_spec.locator('.ms-val').evaluate(r'(node) => parseInt(getComputedStyle(node).color.match(/\d+/)[0]) > 180'), 'Dark spec value must be readable'
        for rect in legend.locator('li').evaluate_all('(nodes) => nodes.map(n => n.getBoundingClientRect().right)'):
            assert rect <= 375, rect
        for rect in page.locator('.owner-alloc > *').evaluate_all('(nodes) => nodes.map(n => n.getBoundingClientRect().right)'):
            assert rect <= 375, rect

        page.set_viewport_size({'width': 1440, 'height': 1000})
        page.evaluate("localStorage.setItem('hutube_lang', 'en')")
        load(family)
        expect(page.locator('.storage-legend')).to_contain_text('You (plan owner)')
        expect(page.locator('.storage-legend')).to_contain_text('Free space')
        shared = {**family, 'isSharedMember': True, 'storageLimit': 8 * gb, 'usedStorage': 3 * gb,
                  'remainingStorage': 5 * gb, 'members': [member('alice')], 'storageUsageBreakdown': None,
                  'sharedOwnerDisplayName': 'Owner', 'ownerAllocatedStorage': None}
        load(shared)
        expect(page.locator('.family-storage-bar')).to_have_count(0)
        expect(page.locator('.quota-allocation-bar')).to_have_count(0)
        expect(page.locator('.shared-member-quota-note')).to_be_visible()

        page.evaluate("localStorage.setItem('hutube_lang', 'vi')")
        last = {**family, 'members': [member('alice')], 'usedStorage': 5 * gb, 'remainingStorage': 25 * gb,
                'storageUsageBreakdown': family['storageUsageBreakdown'][:2]}
        load(last)
        page.locator('.members-table .btn-revoke').click()
        expect(page.locator('.quota-allocation-bar')).to_have_count(0)
        expect(page.locator('.storage-legend')).to_contain_text('An (đã rời nhóm)')
        assert revokes == ['alice']
        assert not errors, errors
        browser.close()
    (args.artifacts / 'result.json').write_text(json.dumps(dict(status='passed', segment_widths=widths, revokes=revokes, errors=errors), indent=2), encoding='utf-8')
    print('PASS: solo/pending/family/member visibility, exact per-person usage/free space, zero usage, vi/en, narrow/dark and last-member revocation')


if __name__ == '__main__':
    main()
