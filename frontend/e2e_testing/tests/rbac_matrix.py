"""Real browser/HTTP matrix for all 50 permissions; owned loopback DB only."""
import argparse
import json
import re
import sys
import uuid
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from playwright.sync_api import expect, sync_playwright
from support.web_suite import WebSuite
from support.state import atomic_json

CATALOGUE_ONLY = set()
ROUTES = [
    ('dashboard.view', '/system/reports', 'app-system-reports-page'),
    ('user.view', '/users', 'app-admin-users-page'),
    ('role.view', '/roles', 'app-admin-rbac-page'),
    ('channel.view', '/channels', 'app-admin-channels-page'),
    ('video.view', '/videos', 'app-admin-videos-page'),
    ('moderation.view_queue', '/moderation/videos', 'app-admin-moderation-page'),
    ('audit.view', '/system/logs', 'app-system-logs-page'),
    ('system.view_setting', '/system/notifications', 'app-system-notifications-page'),
    ('taxonomy.manage', '/topics', 'app-admin-topics-page'),
    ('cf_seed.manage', '/cf-seeder', 'app-cf-seeder-page'),
    ('plan.view', '/plans', 'app-admin-plans-page'),
    ('payment.view', '/payments', 'app-admin-payments-page'),
    ('policy.view', '/policies', 'app-admin-policies-page'),
    ('report.view', '/moderation/reports', 'app-admin-reports-page'),
    ('appeal.view', '/moderation/appeals', 'app-admin-appeals-page'),
    ('strike.view', '/moderation/strikes', 'app-admin-strikes-page'),
]
ACTION_CONTROLS = [
    ('role.edit', 'role.view', '/roles', '.heading-actions .primary-action'),
    ('role.delete', 'role.view', '/roles', '.heading-actions .danger-action'),
    ('plan.create', 'plan.view', '/plans', '.heading-actions .primary-action'),
    ('plan.edit', 'plan.view', '/plans', 'tbody .icon-action:not(.danger)'),
    ('plan.archive', 'plan.view', '/plans', 'tbody .icon-action.danger'),
    ('policy.manage', 'policy.view', '/policies', '.header-actions .btn-primary'),
    ('system.edit_setting', 'policy.view', '/policies', '.header-actions .btn-primary'),
    ('taxonomy.manage', 'system.view_setting', '/topics', '.heading-actions .btn-primary'),
    ('strike.manage', 'strike.view', '/moderation/strikes', '.header-actions .btn-primary'),
    ('channel.lock', 'strike.view', '/moderation/strikes', '.header-actions .btn-secondary:not(.btn-icon-only)'),
    ('channel.export', 'channel.view', '/channels', '[data-testid=channel-export]'),
    ('video.export', 'video.view', '/videos', '[data-testid=video-export]'),
]
READS = {
    'dashboard.view': '/admin/operations/reports', 'user.view': '/admin/users',
    'role.view': '/admin/roles', 'channel.view': '/admin/channels',
    'video.view': '/admin/videos', 'moderation.view_queue': '/admin/moderation/queue',
    'audit.view': '/admin/audit-logs', 'system.view_setting': '/admin/operations/system',
    'cf_seed.manage': '/admin/cf-seeder/users', 'plan.view': '/admin/plans',
    'payment.view': '/admin/payments', 'policy.view': '/admin/policies',
    'report.view': '/admin/reports/cases', 'appeal.view': '/admin/appeals',
    'strike.view': '/admin/strikes',
}


def uid():
    return str(uuid.uuid4())


class Matrix:
    def __init__(self, suite):
        self.s = suite
        self.admin = suite.actor('rbac-superadmin', 'super_admin')
        self.owner = suite.actor('rbac-owner')
        permissions = self.call(self.admin, 'get', '/admin/permissions').json()
        self.codes = sorted(p['code'] for p in permissions if p['status'] == 'active')
        # Fail on catalogue drift: a new permission must get a scenario, not disappear.
        source = (ROOT.parents[1] / 'backend/src/HuTube.Domain/Rbac/Rbac.cs').read_text(encoding='utf-8')
        constants = re.findall(r'public const string \w+ = "([a-z_]+\.[a-z_]+)";', source.split('public static class AdminPermissions')[1].split('public sealed class Permission')[0])
        assert set(self.codes) == set(constants) and len(self.codes) == 50
        assert len({c.split('.')[0] for c in self.codes}) == 16
        self.role = self.call(self.admin, 'post', '/admin/roles', data={
            'code': 'matrix_' + uid().replace('-', ''), 'name': 'RBAC isolated matrix',
            'permissionCodes': self.codes, 'reason': 'Owned local permission matrix',
        }).json()
        self.actor = suite.actor('rbac-subject', self.role['code'])
        self.original_token = self.actor['headers']['Authorization']
        self.records = []

    def call(self, actor, method, path, expected=(200, 201, 204), **kwargs):
        response = self.s.api(actor, method, path, **kwargs)
        assert response.status in expected, f'{method} {path}: HTTP {response.status}: {response.text()[:350]}'
        return response

    def grant(self, codes):
        self.call(self.admin, 'put', '/admin/roles/' + self.role['roleId'], data={
            'name': self.role['name'], 'permissionCodes': sorted(set(codes)),
            'reason': 'RBAC matrix grant/revoke without signing in again',
        })

    def identity(self, codes):
        response = self.call(self.actor, 'get', '/admin/me').json()
        assert set(response['permissions']) == set(codes)
        assert response['role'] == self.role['code']

    def sentinel(self, permission):
        # Keep the admin session valid while excluding every OR alternative.
        return 'user.view' if permission == 'dashboard.view' else 'dashboard.view'

    def case(self, permission, suffix, action, expected):
        case_id = 'RBAC-' + permission.upper().replace('.', '-').replace('_', '-') + '-' + suffix
        self.s.case(self.actor, case_id, permission + ' — ' + suffix, action,
                    module='rbac-' + permission.split('.')[0], expected=expected,
                    steps='Real role API → existing session → actual HTTP/UI → persisted state read-back')
        entry = self.s.report['cases'][-1]
        entry['permission'] = permission
        entry['coverage_layer'] = suffix
        entry['subject_actor'] = self.actor['name']
        entry['subject_role'] = self.role['code']
        if suffix == 'GRANT-REVOKE-REGRANT' and entry.get('screenshot'):
            # The subject's /admin/me was checked above; the relevant visual
            # evidence is the persisted editor state on the administrator page.
            row = self.admin['page'].locator('.permission-row').filter(
                has=self.admin['page'].locator('small').get_by_text(permission, exact=True))
            if entry['status'] == 'passed':
                row.scroll_into_view_if_needed()
            self.admin['page'].screenshot(path=str(ROOT / entry['screenshot']), full_page=True, animations='disabled')
            entry['screenshot_actor'] = self.admin['name']
        entry['business_endpoint_available'] = permission not in CATALOGUE_ONLY
        self.s.flush()

    def propagation(self, permission):
        sentinel = self.sentinel(permission)
        def action():
            self.grant([sentinel, permission])
            self.identity([sentinel, permission])
            self.grant([sentinel])
            self.identity([sentinel])
            # Read the real Admin role editor after revocation, then after regrant.
            self.s.go(self.admin, '/roles', 'app-admin-rbac-page')
            p = self.admin['page']
            p.locator('.role-browser input[type=search]').fill(self.role['code'])
            p.locator('.role-card').click()
            row = p.locator('.permission-row').filter(has=p.locator('small').get_by_text(permission, exact=True))
            expect(row).to_have_count(1)
            expect(row).not_to_have_class(re.compile('is-granted'))
            self.grant([sentinel, permission])
            self.identity([sentinel, permission])
            self.s.go(self.admin, '/roles', 'app-admin-rbac-page')
            p.locator('.role-browser input[type=search]').fill(self.role['code'])
            p.locator('.role-card').click()
            expect(p.locator('.permission-row').filter(has=p.locator('small').get_by_text(permission, exact=True))).to_have_class(re.compile('is-granted'))
            # Restore the subject identity; case() captures the role editor.
            self.actor['page'].goto(self.s.config['admin_url'] + '/account')
            expect(self.actor['page'].locator('app-account-page')).to_be_visible()
        self.case(permission, 'GRANT-REVOKE-REGRANT', action,
                  'Exact permissions in /admin/me and persisted role UI; same signed-in session')

    def sql(self, statement, variables=None):
        return self.s.db.sql(statement, variables)

    def fixture(self, permission):
        """Arrange valid, disposable state. Never mock authorization or business APIs."""
        if permission in READS:
            return 'get', READS[permission], None, lambda response: None
        if permission in ('channel.export', 'video.export'):
            return 'get', '/admin/' + ('channels' if permission == 'channel.export' else 'videos') + '/export', None, self.verify_export
        token = uid().replace('-', '')
        reason = 'RBAC matrix ' + token
        body = {'reason': reason, 'notifyOwner': False}
        if permission in ('role.edit', 'role.delete'):
            code = 'victim_' + token
            if permission == 'role.edit':
                return 'post', '/admin/roles', dict(code=code, name=code, permissionCodes=['dashboard.view'], reason=reason), lambda r: self.verify('roles', 'code', code, 'name', code)
            role = self.call(self.admin, 'post', '/admin/roles', data=dict(code=code, name=code, permissionCodes=['user.view'], reason=reason)).json()
            return 'delete', '/admin/roles/' + role['roleId'] + '?reason=' + token, None, lambda r: self.verify('roles', 'role_id', role['roleId'], 'status', 'deleted')
        if permission.startswith('plan.'):
            payload = dict(code='matrix_' + token, name='Matrix plan', price=10000, durationDays=30,
                           storageLimit=1073741824, maxUploadSize=1048576, maxVideoDuration=60,
                           maxVideoQuality='720p', maxDownloadQuality='720p', maxMembers=1)
            if permission == 'plan.create':
                return 'post', '/admin/plans', payload, lambda r: self.verify('plans', 'code', payload['code'], 'name', payload['name'])
            plan = self.call(self.admin, 'post', '/admin/plans', data=payload).json()
            if permission == 'plan.edit':
                payload.update(name='Edited ' + token, status='active')
                return 'put', '/admin/plans/' + plan['planId'], payload, lambda r: self.verify('plans', 'plan_id', plan['planId'], 'name', payload['name'])
            return 'post', '/admin/plans/' + plan['planId'] + '/archive', {}, lambda r: self.verify('plans', 'plan_id', plan['planId'], 'status', 'archived')
        if permission in ('policy.manage', 'system.edit_setting'):
            payload = dict(code='MATRIX.' + token.upper(), name=reason, group='content', content=reason,
                           severity='low', version='1.0', status='published')
            return 'post', '/admin/policies', payload, lambda r: self.verify('policies', 'code', payload['code'], 'name', reason)
        if permission == 'taxonomy.manage':
            payload = dict(name=reason, slug='matrix-' + token, description=reason)
            return 'post', '/admin/topics', payload, lambda r: self.verify('categories', 'slug', payload['slug'], 'name', reason)
        if permission in ('user.edit', 'user.ban'):
            # Separate from actor/owner, so a ban cannot destroy later fixtures.
            target = self.s.actor('matrix-target-' + token[:8])
            target_id = target['user_id']
            if permission == 'user.edit':
                return 'put', '/admin/users/' + target_id + '/role', dict(roleCode='moderator', reason=reason), lambda r: self.verify('users', 'user_id', target_id, 'role_id', '00000000-0000-0000-0000-000000000004')
            return 'post', '/admin/users/' + target_id + '/lock', body, lambda r: self.verify('users', 'user_id', target_id, 'status', 'banned')
        # Distinct fixture channel/video for each decision and each regrant replay.
        cid, vid = uid(), uid()
        self.target_fixture = dict(channelId=cid, videoId=vid, title=reason)
        self.sql("""INSERT INTO channels(channel_id,owner_user_id,name,handle,status,created_at,updated_at)
            VALUES(:'cid'::uuid,:'owner'::uuid,:'name',:'handle','active',now(),now());
            INSERT INTO videos(video_id,channel_id,uploaded_by_user_id,title,video_url,duration,file_size,
                visibility,status,moderation_status,published_at,created_at,updated_at)
            VALUES(:'vid'::uuid,:'cid'::uuid,:'owner'::uuid,:'name','https://example.test/matrix.mp4',60,1024,
                'public','published','approved',now(),now(),now());""",
                 dict(cid=cid, vid=vid, owner=self.owner['user_id'], name=reason, handle='m_' + token))
        if permission.startswith('channel.'):
            action = permission.split('.')[1]
            if action == 'edit':
                payload = dict(name='Edited ' + token, description=reason, contactEmail='matrix@example.test', reason=reason)
                return 'put', '/admin/channels/' + cid + '/metadata', payload, lambda r: self.verify('channels', 'channel_id', cid, 'name', payload['name'])
            if action == 'strike':
                return 'post', '/admin/channels/' + cid + '/strikes', dict(severity='high', reason=reason), lambda r: self.verify('channel_strikes', 'strike_id', r.json()['strikeId'], 'status', 'active')
            if action == 'remove_strike':
                strike = self.call(self.admin, 'post', '/admin/strikes', data=dict(channelId=cid, severity='high', reason=reason)).json()
                self.target_fixture['strikeId'] = strike['strikeId']
                return 'post', '/admin/channels/' + cid + '/strikes/' + strike['strikeId'] + '/revoke', body, lambda r: self.verify('channel_strikes', 'strike_id', strike['strikeId'], 'status', 'revoked')
            if action == 'unban':
                self.sql("UPDATE channels SET status='banned' WHERE channel_id=:'id'::uuid;", {'id': cid})
            method = 'delete' if action == 'delete' else 'post'
            path = '/admin/channels/' + cid + ('' if action == 'delete' else '/' + action)
            status = dict(suspend='suspended', ban='banned', unban='active', delete='deleted', lock='suspended')[action]
            return method, path, body, lambda r: self.verify('channels', 'channel_id', cid, 'status', status)
        if permission.startswith('video.'):
            action = permission.split('.')[1]
            if action == 'strike':
                return 'post', '/admin/videos/' + vid + '/strikes', dict(severity='high', reason=reason), lambda r: self.verify('channel_strikes', 'strike_id', r.json()['strikeId'], 'channel_id', cid)
            if action == 'view_private':
                self.sql("UPDATE videos SET visibility='private' WHERE video_id=:'id'::uuid;", {'id': vid})
                self.private_channel_id = cid
                return 'get', '/admin/videos/' + vid, None, lambda r: self.private_visible(r, vid)
            if action == 'edit_metadata':
                payload = dict(title='Edited ' + token, description=reason, reason=reason, clearCategory=False)
                return 'put', '/admin/videos/' + vid + '/metadata', payload, lambda r: self.verify('videos', 'video_id', vid, 'title', payload['title'])
            if action in ('unhide', 'restore'):
                self.call(self.admin, 'post', '/admin/videos/' + vid + '/hide', data=body)
            state = 'published' if action in ('unhide', 'restore') else 'blocked'
            return 'post', '/admin/videos/' + vid + '/' + action, body, lambda r: self.verify('videos', 'video_id', vid, 'status', state)
        if permission == 'strike.manage':
            return 'post', '/admin/strikes', dict(channelId=cid, severity='low', reason=reason), lambda r: self.verify('channel_strikes', 'strike_id', r.json()['strikeId'], 'status', 'active')
        mid = uid()
        if permission.startswith('moderation.'):
            self.sql("""UPDATE videos SET status='processing',moderation_status='pending' WHERE video_id=:'vid'::uuid;
                INSERT INTO moderation_cases(moderation_case_id,video_id,case_type,status,submitted_at,updated_at)
                VALUES(:'mid'::uuid,:'vid'::uuid,'upload_review','pending',now(),now());""", dict(vid=vid, mid=mid))
            if permission == 'moderation.claim':
                return 'post', '/admin/moderation/' + mid + '/claim', {}, lambda r: self.verify('moderation_cases', 'moderation_case_id', mid, 'reviewer_id', self.actor['user_id'])
            claim = self.lease('moderation_cases', 'moderation_case_id', mid)
            decision = {'moderation.review': 'escalate', 'moderation.approve': 'approve', 'moderation.reject': 'reject'}[permission]
            policy = self.sql("SELECT code FROM policies WHERE status='published' AND effective_at<=now() ORDER BY code LIMIT 1;")
            return 'post', '/admin/moderation/' + mid + '/resolve', dict(decision=decision, reason=reason, policyCode=policy, claimId=claim), lambda r: self.verify('moderation_cases', 'moderation_case_id', mid, 'status', dict(escalate='escalated', approve='approved', reject='rejected')[decision])
        if permission.startswith('report.'):
            rid = uid()
            self.sql("""INSERT INTO reports(report_id,user_id,violation_type_id,video_id,description,status,created_at,updated_at)
                VALUES(:'rid'::uuid,:'owner'::uuid,(SELECT violation_type_id FROM violation_types WHERE status='active' LIMIT 1),:'vid'::uuid,'Matrix report','pending',now(),now());
                INSERT INTO moderation_cases(moderation_case_id,case_type,target_type,target_id,status,submitted_at,updated_at)
                VALUES(:'mid'::uuid,'report_case','video',:'vid'::uuid,'pending',now(),now());
                UPDATE reports SET moderation_case_id=:'mid'::uuid,disposition='rejected' WHERE report_id=:'rid'::uuid;""", dict(rid=rid, vid=vid, mid=mid, owner=self.owner['user_id']))
            if permission == 'report.claim':
                return 'post', '/admin/reports/cases/' + mid + '/claim', {}, lambda r: self.verify('moderation_cases', 'moderation_case_id', mid, 'reviewer_id', self.actor['user_id'])
            claim = self.lease('moderation_cases', 'moderation_case_id', mid)
            return 'post', '/admin/reports/cases/' + mid + '/resolve', dict(decision='dismiss', reason=reason, claimId=claim), lambda r: self.verify('moderation_cases', 'moderation_case_id', mid, 'status', 'resolved')
        if permission == 'appeal.resolve':
            aid = uid()
            self.sql("""INSERT INTO appeals(appeal_id,user_id,target_type,target_id,reason,status,created_at,updated_at)
                VALUES(:'aid'::uuid,:'owner'::uuid,'video',:'vid'::uuid,'Matrix appeal','pending',now(),now());""", dict(aid=aid, vid=vid, owner=self.owner['user_id']))
            claim = self.lease('appeals', 'appeal_id', aid)
            return 'post', '/admin/appeals/' + aid + '/resolve', dict(decision='reject', reviewNote=reason, claimId=claim), lambda r: self.verify('appeals', 'appeal_id', aid, 'status', 'rejected')
        raise AssertionError('Missing scenario for ' + permission)

    def lease(self, table, key, value):
        claim = uid()
        self.sql(f"UPDATE {table} SET reviewer_id=:'actor'::uuid,status='reviewing',claimed_at=now(),claim_id=:'claim'::uuid,claim_expires_at=now()+interval '15 minutes' WHERE {key}=:'id'::uuid;",
                 dict(actor=self.actor['user_id'], claim=claim, id=value))
        return claim

    def verify(self, table, key, value, field, expected):
        actual = self.sql(f"SELECT {field}::text FROM {table} WHERE {key}::text=:'id';", {'id': value})
        assert actual == expected, f'{table}.{field}: expected {expected}, got {actual}'

    def private_visible(self, response, vid):
        assert response.json()['video']['videoId'] == vid
        assert response.json()['video']['visibility'] == 'private'
        listing = self.call(self.actor, 'get', '/admin/videos', params={'channelId': self.private_channel_id}).json()
        assert [v['videoId'] for v in listing['items']] == [vid]

    def verify_export(self, response):
        result = response.json()
        assert result['total'] == len(result['items'])
        assert len({r.get('channelId') if 'videoId' not in r else r['videoId'] for r in result['items']}) == result['total']

    def snapshot(self):
        # Permission denial audit events are expected; business data must not change.
        tables = ['users', 'roles', 'channels', 'videos', 'plans', 'policies', 'categories',
                  'moderation_cases', 'reports', 'appeals', 'channel_strikes']
        return self.sql('SELECT json_build_array(' + ','.join(
            f"(SELECT md5(COALESCE(string_agg(row_to_json(t)::text,'' ORDER BY row_to_json(t)::text),'')) FROM {t} t)" for t in tables) + ')::text;')

    def business(self, permission):
        # Browser restore rotates the login session. Capture AFTER the UI steps,
        # then reuse this still-valid token across grant/revoke HTTP requests.
        self.original_token = self.actor['headers']['Authorization']
        base = [self.sentinel(permission)]
        if permission == 'video.view_private':
            base.append('video.view')
        denied = 404 if permission == 'video.view_private' else 403
        for phase in ('ANONYMOUS', 'DENIED', 'ALLOWED', 'REVOKED'):
            def action(phase=phase):
                method, path, body, verify = self.fixture(permission)
                alternatives = {
                    'policy.view': {'policy.view', 'system.view_setting', 'moderation.review', 'moderation.view_queue'},
                    'policy.manage': {'policy.manage', 'system.edit_setting'},
                    'system.edit_setting': {'policy.manage', 'system.edit_setting'},
                }.get(permission, {permission})
                granted = base + [permission] if phase == 'ALLOWED' else sorted(set(self.codes) - alternatives)
                self.grant(granted)
                self.identity(granted)
                before = self.snapshot()
                # Explicitly use the original access token for revoke checks.
                original = self.actor['headers']['Authorization']
                self.actor['headers']['Authorization'] = self.original_token
                try:
                    if phase == 'ANONYMOUS':
                        context = self.s.browser.new_context()
                        try:
                            response = getattr(context.request, method)(self.s.config['api_url'] + path,
                                **({'data': body} if body is not None else {}))
                            assert response.status == 401, f'Anonymous {method} {path}: HTTP {response.status}'
                        finally:
                            context.close()
                    else:
                        response = self.call(self.actor, method, path,
                            expected=(200, 201, 204) if phase == 'ALLOWED' else (denied,),
                            **({'data': body} if body is not None else {}))
                finally:
                    self.actor['headers']['Authorization'] = original
                if phase == 'ALLOWED':
                    verify(response)
                else:
                    assert self.snapshot() == before, 'Denied request modified business data'
                    if permission == 'video.view_private' and phase != 'ANONYMOUS':
                        listing = self.call(self.actor, 'get', '/admin/videos', params={'channelId': self.private_channel_id}).json()
                        assert listing['items'] == [] and listing['total'] == 0
                    if denied == 403 and phase != 'ANONYMOUS':
                        assert response.json()['code'] == 'PERMISSION_DENIED'
                self.records.append(dict(permission=permission, phase=phase, method=method, path=path, status=response.status))
            self.case(permission, 'API-' + phase, action,
                      '2xx + persisted state' if phase == 'ALLOWED' else f'{401 if phase == "ANONYMOUS" else denied}; business data unchanged')

    def routes(self):
        for permission, route, component in ROUTES:
            for allowed in (True, False):
                def action(permission=permission, route=route, component=component, allowed=allowed):
                    codes = [self.sentinel(permission)] + ([permission] if allowed else [])
                    self.grant(codes)
                    self.actor['page'].goto(self.s.config['admin_url'] + route)
                    if allowed:
                        expect(self.actor['page'].locator(component)).to_be_visible()
                        assert self.actor['page'].url.split('?')[0].endswith(route)
                    else:
                        self.actor['page'].wait_for_url('**/forbidden')
                        expect(self.actor['page'].locator(component)).to_have_count(0)
                self.case(permission, 'UI-ALLOW' if allowed else 'UI-DENY', action,
                          'Protected page visible' if allowed else '/forbidden; protected component absent')

    def controls(self):
        for permission, view, route, selector in ACTION_CONTROLS:
            for allowed in (True, False):
                def action(permission=permission, view=view, route=route, selector=selector, allowed=allowed):
                    self.grant([view, permission] if allowed else [view])
                    self.actor['page'].goto(self.s.config['admin_url'] + route)
                    p = self.actor['page']
                    if route == '/roles':
                        expect(p.locator('.role-browser input[type=search]')).to_be_visible()
                        p.locator('.role-browser input[type=search]').fill(self.role['code'])
                        p.locator('.role-card').click()
                    else:
                        component = next(component for _, r, component in ROUTES if r == route)
                        expect(p.locator(component)).to_be_visible()
                    # Wait for actual data, so an absent button during loading
                    # cannot count as a denied-control pass.
                    if route == '/plans':
                        expect(p.locator('.plan-name').first).to_be_visible()
                    if route == '/policies':
                        expect(p.locator('.header-actions .btn-secondary')).to_be_enabled()
                    button = p.locator(selector)
                    if allowed:
                        expect(button.first).to_be_visible()
                        expect(button.first).to_be_enabled()
                        if permission.endswith('.export'):
                            import csv
                            with p.expect_download() as pending:
                                button.first.click()
                            download = pending.value
                            destination = self.s.run_dir / 'downloads' / (permission + '.csv')
                            destination.parent.mkdir(exist_ok=True)
                            download.save_as(str(destination))
                            rows = list(csv.reader(destination.read_text(encoding='utf-8-sig').splitlines()))
                            assert len(rows) > 1
                            api_path = '/admin/' + ('channels' if permission == 'channel.export' else 'videos') + '/export'
                            expected_rows = self.call(self.actor, 'get', api_path).json()['items']
                            id_key = 'channelId' if permission == 'channel.export' else 'videoId'
                            assert {r[0] for r in rows[1:]} == {r[id_key] for r in expected_rows}
                    else:
                        expect(button).to_have_count(0)
                self.case(permission, 'UI-CONTROL-ALLOW' if allowed else 'UI-CONTROL-DENY', action,
                          'Action visible and enabled' if allowed else 'Read access retained; mutation action absent')

    def target_actions(self):
        for permission in ('channel.edit', 'channel.strike', 'channel.remove_strike', 'video.strike'):
            for allowed in (True, False):
                def action(permission=permission, allowed=allowed):
                    method, path, body, verify = self.fixture(permission)
                    fixture = self.target_fixture
                    is_video = permission.startswith('video.')
                    self.grant((['video.view'] if is_video else ['channel.view']) + ([permission] if allowed else []))
                    p = self.actor['page']
                    route = '/videos' if is_video else '/channels'
                    self.s.go(self.actor, route, 'app-admin-videos-page' if is_video else 'app-admin-channels-page')
                    p.locator('.search-box input').fill(fixture['title'])
                    p.locator('.btn-filter').click()
                    row = p.locator('.video-row' if is_video else '.channel-row').filter(has_text=fixture['title'])
                    expect(row).to_have_count(1)
                    row.click()
                    expect(p.locator('app-admin-target-actions')).to_be_visible()
                    test_id = permission.replace('.', '-').replace('_', '-')
                    button = p.get_by_test_id(test_id)
                    if not allowed:
                        expect(button).to_have_count(0)
                        return
                    expect(button).to_be_visible()
                    button.click()
                    dialog = p.locator('app-admin-target-actions app-confirm-dialog dialog:modal')
                    expect(dialog.locator('.confirm-submit')).to_be_disabled()
                    before = self.snapshot()
                    dialog.locator('.confirm-cancel').click()
                    assert self.snapshot() == before
                    button.click()
                    if permission == 'channel.edit':
                        p.get_by_test_id('target-name').fill(body['name'])
                        p.get_by_test_id('target-description').fill(body['description'])
                        p.get_by_test_id('target-email').fill(body['contactEmail'])
                    if permission == 'channel.remove_strike':
                        expect(p.get_by_test_id('target-strike-id').locator('option')).to_have_count(2)
                        p.get_by_test_id('target-strike-id').select_option(fixture['strikeId'])
                    p.get_by_test_id('target-reason').fill(body['reason'])
                    with p.expect_response(lambda r: r.request.method == method.upper() and r.url.endswith(path)) as pending:
                        dialog.locator('.confirm-submit').click()
                    assert pending.value.status in (200, 201, 204)
                    verify(pending.value)
                    expect(dialog).to_have_count(0)
                self.case(permission, 'UI-ACTION-ALLOW' if allowed else 'UI-ACTION-DENY', action,
                          'Reason required; cancel unchanged; actual UI submit persists mutation' if allowed else 'Read access remains; action hidden')

    def boundaries(self):
        def user_role():
            self.grant(self.codes)
            assert any(r['code'] == 'user' for r in self.call(self.admin, 'get', '/admin/roles').json())
            assert not any(r['code'] == 'user' for r in self.call(self.actor, 'get', '/admin/roles').json())
            self.s.go(self.actor, '/roles', 'app-admin-rbac-page')
            self.actor['page'].locator('.role-browser input[type=search]').fill('user')
            expect(self.actor['page'].locator('.role-card small').get_by_text('user', exact=True)).to_have_count(0)
            self.call(self.actor, 'put', '/admin/users/' + self.owner['user_id'] + '/role',
                      data={'roleCode': 'user', 'reason': 'Non-Super Admin cannot assign protected User'}, expected=(403,))
        self.case('role.view', 'SUPERADMIN-USER-ROLE', user_role, 'User role visible/assignable only for Super Admin')

        def delegation():
            self.grant(['dashboard.view', 'role.edit'])
            code = 'no_escalation_' + uid().replace('-', '')[:20]
            response = self.call(self.actor, 'post', '/admin/roles', data={
                'code': code, 'name': code, 'permissionCodes': ['video.remove'], 'reason': 'Cannot delegate absent permission'}, expected=(403,))
            assert response.json()['code'] == 'PERMISSION_DELEGATION_DENIED'
            assert self.sql("SELECT count(*) FROM roles WHERE code=:'code';", {'code': code}) == '0'
        self.case('role.edit', 'NO-PRIVILEGE-ESCALATION', delegation, '403; cannot create a role granting an unowned permission')

        def assigned_delete():
            self.grant(['role.view', 'role.delete'])
            code = 'assigned_' + uid().replace('-', '')[:20]
            victim = self.call(self.admin, 'post', '/admin/roles', data={
                'code': code, 'name': code, 'permissionCodes': ['dashboard.view'], 'reason': 'Assigned role fixture'}).json()
            target = self.s.actor('removed_' + code[-8:], code)
            p = self.actor['page']
            self.s.go(self.actor, '/roles', 'app-admin-rbac-page')
            p.locator('.role-browser input[type=search]').fill(code)
            p.locator('.role-card').click()
            expect(p.locator('.role-summary')).to_contain_text(code)
            p.locator('.heading-actions .danger-action').click()
            dialog = p.locator('app-confirm-dialog dialog:modal')
            expect(dialog).to_be_visible()
            expect(dialog.locator('.confirm-submit')).to_be_disabled()
            # A cancel must preserve both the assignment and role.
            dialog.locator('.confirm-cancel').click()
            self.verify('users', 'user_id', target['user_id'], 'role_id', victim['roleId'])
            p.locator('.heading-actions .danger-action').click()
            dialog.locator('textarea').fill('Confirmed delete: unassign member, allow later reassignment')
            with p.expect_response(lambda r: r.request.method == 'DELETE' and '/admin/roles/' + victim['roleId'] in r.url) as pending:
                dialog.locator('.confirm-submit').click()
            assert pending.value.status == 204
            self.verify('roles', 'role_id', victim['roleId'], 'status', 'deleted')
            assert self.sql("SELECT role_id IS NULL FROM users WHERE user_id=:'id'::uuid;", {'id': target['user_id']}) == 't'
            self.call(target, 'get', '/admin/me', expected=(401, 403))
            self.call(self.admin, 'put', '/admin/users/' + target['user_id'] + '/role', data={'roleCode': 'user', 'reason': 'Reassign removed member later'})
            self.verify('users', 'user_id', target['user_id'], 'role_id', '00000000-0000-0000-0000-000000000001')
        self.case('role.delete', 'DELETE-ASSIGNED-ROLE', assigned_delete,
                  'Reason required; cancel preserves; confirm soft-deletes, unassigns member, revokes admin access; reassignment succeeds')

        def system_role():
            self.grant(['role.view', 'role.delete'])
            role = next(r for r in self.call(self.admin, 'get', '/admin/roles').json() if r['code'] == 'super_admin')
            before = self.snapshot()
            self.call(self.actor, 'delete', '/admin/roles/' + role['roleId'] + '?reason=Protected-system-role', expected=(403,))
            assert self.snapshot() == before
        self.case('role.delete', 'PROTECTED-SYSTEM-ROLE', system_role, 'System role cannot be deleted even with role.delete')

        def channel_validation():
            method, path, body, _ = self.fixture('channel.edit')
            cid = self.target_fixture['channelId']
            self.grant(['channel.edit'])
            before = self.snapshot()
            for invalid in (dict(body, name=' '), dict(body, contactEmail='invalid-email'), dict(body, reason='')):
                self.call(self.actor, method, path, data=invalid, expected=(400,))
                assert self.snapshot() == before
            original = self.sql("SELECT json_build_array(owner_user_id,handle)::text FROM channels WHERE channel_id=:'id'::uuid;", {'id': cid})
            self.call(self.actor, method, path, data=body)
            assert self.sql("SELECT json_build_array(owner_user_id,handle)::text FROM channels WHERE channel_id=:'id'::uuid;", {'id': cid}) == original
            assert self.sql("SELECT count(*) FROM audit_logs WHERE resource_id=:'id'::uuid AND action='admin.channel.metadata_updated';", {'id': cid}) == '1'
        self.case('channel.edit', 'VALIDATION-AUDIT', channel_validation, 'Invalid name/email/reason: 400 without writes; valid edit preserves handle/owner and records audit')

        def revoke_scope():
            _, _, _, _ = self.fixture('channel.remove_strike')
            first = dict(self.target_fixture)
            self.fixture('channel.strike')
            second = dict(self.target_fixture)
            self.grant(['channel.remove_strike'])
            before = self.snapshot()
            wrong = '/admin/channels/' + second['channelId'] + '/strikes/' + first['strikeId'] + '/revoke'
            self.call(self.actor, 'post', wrong, data={'reason': 'Cross-channel ID must not revoke another channel'}, expected=(404,))
            assert self.snapshot() == before
            assert self.call(self.actor, 'get', '/admin/channels/' + second['channelId'] + '/strikes').json() == []
            own = self.call(self.actor, 'get', '/admin/channels/' + first['channelId'] + '/strikes').json()
            assert [s['strikeId'] for s in own] == [first['strikeId']]
        self.case('channel.remove_strike', 'CHANNEL-SCOPE', revoke_scope, 'Mismatched channel/strike ID: 404 without writes; scoped list never returns another channel’s strike')

        def export_pagination():
            prefix = 'matrix_export_' + uid().replace('-', '')
            # Equal timestamps exercise the stable ID tie-breaker across page 100.
            self.sql("""INSERT INTO channels(channel_id,owner_user_id,name,handle,status,created_at,updated_at)
                SELECT gen_random_uuid(),:'owner'::uuid,'=SUM(1,1) '||:'prefix'||i,:'prefix'||i,'active',now(),now() FROM generate_series(1,105) i;
                INSERT INTO videos(video_id,channel_id,uploaded_by_user_id,title,video_url,duration,file_size,
                    visibility,status,moderation_status,published_at,created_at,updated_at)
                SELECT gen_random_uuid(),channel_id,:'owner'::uuid,'=SUM(1,1) '||:'prefix'||row_number() OVER (ORDER BY channel_id),
                    'https://example.test/export.mp4',60,1024,
                    CASE WHEN row_number() OVER (ORDER BY channel_id)%2=0 THEN 'private' ELSE 'public' END,
                    'published','approved',now(),now(),now() FROM channels WHERE handle LIKE :'prefix'||'%';""",
                     {'owner': self.owner['user_id'], 'prefix': prefix})
            self.export_prefix = prefix
            self.grant(['channel.export'])
            channels = self.call(self.actor, 'get', '/admin/channels/export', params={'search': prefix}).json()
            assert channels['total'] == 105 and len({c['channelId'] for c in channels['items']}) == 105
            self.grant(['video.export'])
            videos = self.call(self.actor, 'get', '/admin/videos/export', params={'search': prefix}).json()
            assert videos['total'] == 53 and all(v['visibility'] == 'public' for v in videos['items'])
            self.grant(['video.export', 'video.view_private'])
            videos = self.call(self.actor, 'get', '/admin/videos/export', params={'search': prefix}).json()
            assert videos['total'] == 105 and len({v['videoId'] for v in videos['items']}) == 105
        self.case('video.export', 'PAGINATION-PRIVATE-FILTER', export_pagination, '105 records across API pages without duplicates; export alone hides private; view_private allows all 105')

        def csv_filter_safety():
            import csv
            for kind, expected_count in (('channel', 105), ('video', 53)):
                self.grant([kind + '.view', kind + '.export'])
                p = self.actor['page']
                self.s.go(self.actor, '/' + kind + 's', 'app-admin-' + kind + 's-page')
                p.locator('.search-box input').fill(self.export_prefix)
                with p.expect_response(lambda r: r.request.method == 'GET' and '/admin/' + kind + 's?' in r.url and 'search=' in r.url):
                    p.locator('.btn-filter').click()
                with p.expect_download() as pending:
                    p.get_by_test_id(kind + '-export').click()
                destination = self.s.run_dir / 'downloads' / (kind + '-filtered.csv')
                pending.value.save_as(str(destination))
                rows = list(csv.reader(destination.read_text(encoding='utf-8-sig').splitlines()))
                assert len(rows) == expected_count + 1
                assert all(row[1].startswith("'=SUM(1,1) ") and self.export_prefix in row[1] for row in rows[1:])
        self.case('channel.export', 'CSV-FILTER-FORMULA-SAFETY', csv_filter_safety, 'UI exports all filtered rows, excludes other rows/private videos, neutralizes leading formulas as spreadsheet text')

        def video_strike_audit():
            method, path, body, _ = self.fixture('video.strike')
            fixture = dict(self.target_fixture)
            self.grant(['video.strike'])
            before = self.snapshot()
            self.call(self.actor, method, path, data=dict(body, severity='unknown'), expected=(400,))
            self.call(self.actor, method, path, data=dict(body, reason=''), expected=(400,))
            assert self.snapshot() == before
            result = self.call(self.actor, method, path, data=body).json()
            assert result['channelId'] == fixture['channelId']
            assert self.sql("SELECT count(*) FROM audit_logs WHERE resource_id=:'id'::uuid AND action='admin.video.strike' AND new_values::text LIKE '%'||:'strike'||'%';",
                            {'id': fixture['videoId'], 'strike': result['strikeId']}) == '1'
        self.case('video.strike', 'VALIDATION-VIDEO-AUDIT', video_strike_audit, 'Invalid severity/reason cannot write; strike targets owning channel and audit links exact video/strike IDs')

    def run(self):
        for permission in self.codes:
            self.propagation(permission)
            if permission not in CATALOGUE_ONLY:
                self.business(permission)
        self.routes()
        self.controls()
        self.target_actions()
        self.boundaries()

    def finish(self):
        atomic_json(self.s.run_dir / 'rbac-coverage.json', {
            'catalogue_permissions': self.codes, 'group_count': 16,
            'catalogue_only_permissions': sorted(CATALOGUE_ONLY),
            'business_gap': 'None: all 50 permissions have real business API coverage.',
            'requests': self.records, 'cases': self.s.report['cases'],
        })
        self.grant(['dashboard.view'])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--config', type=Path, required=True)
    args = parser.parse_args()
    config = json.loads(args.config.read_text(encoding='utf-8'))
    assert config['api_url'].startswith('http://127.0.0.1:'), 'Local runner only'
    with sync_playwright() as p:
        suite = WebSuite(config, p)
        suite.report['suite'] = 'rbac'
        matrix = None
        try:
            matrix = Matrix(suite)
            matrix.run()
        finally:
            if matrix:
                matrix.finish()
            suite.close()
    return 1 if suite.report['failed'] or suite.report['blocked'] else 0


if __name__ == '__main__':
    sys.exit(main())
