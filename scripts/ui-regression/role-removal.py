"""Verify assigned-role deletion, unassigned users, and Super Admin role visibility."""
import argparse
import json
from datetime import datetime, timedelta, timezone
from pathlib import Path
from urllib.parse import urlparse, parse_qs

from playwright.sync_api import expect, sync_playwright


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--url', default='http://127.0.0.1:4308')
    parser.add_argument('--browser-path')
    parser.add_argument('--artifacts', type=Path, required=True)
    args = parser.parse_args()
    args.artifacts.mkdir(parents=True, exist_ok=True)
    date = datetime.now(timezone.utc).isoformat()
    actor = dict(userId='admin', username='admin', email='admin@example.test', displayName='Administrator',
                 emailVerified=True, isAdmin=True, role='admin', permissions=['role.view', 'role.edit', 'role.delete', 'user.view', 'user.edit'])
    roles = [dict(roleId='review', code='review', name='Review team', description=None, permissions=['user.view'], status='active', isSystemRole=False, assignedUserCount=2),
             dict(roleId='other', code='other', name='Other team', description=None, permissions=['user.view'], status='active', isSystemRole=False, assignedUserCount=0),
             dict(roleId='user', code='user', name='User', description=None, permissions=[], status='active', isSystemRole=True, assignedUserCount=10)]
    member = dict(userId='member', displayName='Kept account', username='kept', email='kept@example.test', avatarUrl=None,
                  roleCode='review', roleName='Review team', planCode=None, planName=None, channelCount=0, warningCount=0,
                  lastLoginAt=None, createdAt=date, status='active', emailVerified=True, lockedUntil=None,
                  permissions=['user.view'], auditHistory=[], channels=[])
    deleted, assigned, errors = [], [], []
    fail_once = True

    def api(route):
        nonlocal fail_once
        request = route.request
        parsed = urlparse(request.url)
        path = parsed.path.split('/api/v1', 1)[-1]
        headers = {'Access-Control-Allow-Origin': request.headers.get('origin', args.url),
                   'Access-Control-Allow-Credentials': 'true',
                   'Access-Control-Allow-Headers': request.headers.get('access-control-request-headers', '*'),
                   'Access-Control-Allow-Methods': 'GET,POST,PUT,PATCH,DELETE,OPTIONS'}

        def respond(data, status=200):
            route.fulfill(status=status, headers=headers, content_type='application/json', body=json.dumps(data))

        if request.method == 'OPTIONS':
            route.fulfill(status=204, headers=headers)
            return
        data = dict(items=[], page=1, pageSize=10, total=0)
        if path == '/auth/refresh':
            data = dict(accessToken='isolated-role-test', expiresAt=(datetime.now(timezone.utc) + timedelta(hours=1)).isoformat(), user=actor)
        elif path in ['/auth/me', '/admin/me']:
            data = actor
        elif path == '/admin/permissions':
            data = [dict(permissionId='view-users', code='user.view', name='Xem Người dùng', description=None, status='active')]
        elif path == '/admin/roles':
            # Return User even to admin to exercise defensive UI filtering.
            data = roles
        elif path.startswith('/admin/roles/') and request.method == 'DELETE':
            deleted.append(dict(role=path.rsplit('/', 1)[-1], reason=parse_qs(parsed.query)['reason'][0]))
            if fail_once:
                fail_once = False
                respond(dict(message='Thử xóa lại'), 503)
                return
            roles[:] = [role for role in roles if role['roleId'] != deleted[-1]['role']]
            member.update(roleCode=None, roleName=None, permissions=[])
            route.fulfill(status=204, headers=headers)
            return
        elif path == '/admin/users':
            data = dict(items=[member], page=1, pageSize=10, total=1, hasMore=False,
                        stats=dict(total=1, active=1, blocked=0, creatorPro=0))
        elif path == '/admin/users/member/role':
            assigned.append(request.post_data_json)
            role = next(role for role in roles if role['code'] == assigned[-1]['roleCode'])
            member.update(roleCode=role['code'], roleName=role['name'])
            data = member
        elif path == '/admin/users/member':
            data = member
        respond(data)

    with sync_playwright() as playwright:
        browser = playwright.chromium.launch(headless=True, executable_path=args.browser_path)
        context = browser.new_context(viewport={'width': 1440, 'height': 1000}, locale='vi-VN')
        context.route('**/api/v1/**', api)
        context.add_init_script("localStorage.setItem('hutube_lang', localStorage.getItem('hutube_lang') || 'vi')")
        page = context.new_page()
        page.on('pageerror', lambda error: errors.append(str(error)))
        page.goto(args.url + '/roles')
        page.wait_for_load_state('networkidle')
        expect(page.locator('.role-list .role-card')).to_have_count(2)
        expect(page.locator('.role-list')).not_to_contain_text('User')
        expect(page.locator('.danger-action')).to_be_enabled()
        page.locator('.danger-action').click()
        dialog = page.get_by_role('dialog')
        expect(dialog).to_contain_text('2 người dùng')
        expect(dialog).to_contain_text('không còn thuộc role nào')
        expect(dialog).to_contain_text('Tài khoản của họ vẫn được giữ')
        assert not deleted
        expect(dialog.locator('.confirm-submit')).to_be_disabled()
        dialog.locator('textarea').fill('Remove old team')
        page.screenshot(path=str(args.artifacts / 'delete-role-assigned-users.png'))
        dialog.locator('.confirm-submit').click()
        expect(dialog.get_by_role('alert')).to_be_visible()
        expect(dialog.locator('textarea')).to_have_value('Remove old team')
        dialog.locator('.confirm-submit').click()
        expect(page.get_by_role('dialog')).to_have_count(0)
        expect(page.locator('.role-list')).not_to_contain_text('Review team')
        assert deleted[0] == deleted[1]

        page.goto(args.url + '/users')
        page.wait_for_load_state('networkidle')
        expect(page.locator('.user-row')).to_contain_text('Chưa có role')
        expect(page.locator('.detail-panel')).to_contain_text('Chưa có role')
        page.locator('.detail-actions').get_by_role('button', name='Cập nhật vai trò', exact=False).click()
        dialog = page.get_by_role('dialog')
        expect(dialog.locator('select[name=actionRole]')).to_have_value('')
        expect(dialog.locator('select[name=actionRole] option[value=user]')).to_have_count(0)
        dialog.locator('textarea').fill('Assign new team')
        expect(dialog.locator('.confirm-submit')).to_be_disabled()
        dialog.locator('select[name=actionRole]').select_option('other')
        dialog.locator('.confirm-submit').click()
        expect(page.get_by_role('dialog')).to_have_count(0)
        expect(page.locator('.user-row')).to_contain_text('Other team')
        assert assigned == [dict(roleCode='other', reason='Assign new team')]

        actor['role'] = 'super_admin'
        page.goto(args.url + '/roles')
        page.wait_for_load_state('networkidle')
        expect(page.locator('.role-list')).to_contain_text('User')
        page.locator('.role-list .role-card').filter(has_text='User').click()
        expect(page.locator('.danger-action')).to_have_count(0)
        page.locator('.role-list .role-card').filter(has_text='Other team').click()
        roles[0]['assignedUserCount'] = 2
        page.reload()
        page.wait_for_load_state('networkidle')
        page.set_viewport_size({'width': 375, 'height': 900})
        page.evaluate("document.documentElement.setAttribute('data-theme', 'dark'); document.body.classList.add('dark-theme')")
        page.locator('.danger-action').click()
        dialog = page.get_by_role('dialog')
        expect(dialog).to_contain_text('2 người dùng')
        page.screenshot(path=str(args.artifacts / 'delete-role-narrow-dark.png'))
        rect = dialog.bounding_box()
        assert rect['x'] >= 0 and rect['x'] + rect['width'] <= 375, rect
        dialog.locator('.confirm-cancel').click()
        assert not errors, errors
        browser.close()
    (args.artifacts / 'result.json').write_text(json.dumps(dict(status='passed', deletes=deleted, assignments=assigned), indent=2), encoding='utf-8')
    print('PASS: assigned-user warning, retry, no-role accounts, reassignment, Super Admin visibility and protected User role, narrow/dark confirmation')


if __name__ == '__main__':
    main()
