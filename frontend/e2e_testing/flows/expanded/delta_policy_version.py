"""Draft editing and immutable moderation policy-version evidence on actual DB."""
import shutil
import subprocess
import time
from playwright.sync_api import expect
from flows.expanded.common import case, snapshot_module
from support.local_db import LocalDb


def run(suite, config, actors):
    snapshot_module(suite, __file__)
    admin, owner, reviewer = actors['admin'], actors['owner'], actors['reviewer1']
    p = admin['page']
    db = LocalDb(config)
    policy = {}
    video = {}
    code = 'DELTA.PIN.' + suite.run_id[9:15]
    def policies():
        return suite.api(admin, 'get', '/admin/policies').json()
    def publish_ui(record, version, content):
        suite.go(admin, '/policies', 'app-admin-policies-page', '/admin/policies')
        p.locator('.search-wrap input').fill(code)
        row = p.locator('.data-table tbody tr').filter(has_text=record['version']).filter(has_text=code)
        expect(row).to_have_count(1)
        row.locator('button').click()
        modal = p.locator('.modal-dialog')
        modal.locator('input[type=text]').fill(version)
        modal.locator('textarea').fill(content)
        return suite.response(admin, '/admin/policies/' + record['policyId'] + '/publish',
            lambda: modal.locator('.modal-footer .btn-primary').click(), method='PUT').json()
    try:
        def draft(entry):
            policy.update(suite.api(admin, 'post', '/admin/policies', data={
                'code': code, 'name': 'Delta draft policy', 'group': 'guidelines', 'content': 'Unpublished draft',
                'severity': 'medium', 'version': '0.1', 'status': 'draft',
            }, expected=201).json())
            assert not any(v['code'] == code for v in suite.api(owner, 'get', '/policies').json())
            original_id = policy['policyId']
            policy.update(publish_ui(policy, '1.0', 'First published delta policy'))
            assert policy['policyId'] == original_id and policy['status'] == 'published'
            assert policy['content'] == 'First published delta policy'
            public = next(v for v in suite.api(owner, 'get', '/policies').json() if v['code'] == code)
            assert public['policyId'] == original_id and public['version'] == '1.0'
            p.reload()
            expect(p.locator('.data-table tbody tr').filter(has_text=code)).to_have_count(1)
            entry['resource_ids'] = [original_id]
            entry['steps'] = ['Real draft excluded from public policy list', 'Edit draft version/content in actual Admin modal then publish', 'Draft identity preserved; exact edited content/version becomes public', 'Reload Admin retains published draft result']
        if not case(suite, admin, 'DELTA-POLICY-DRAFT-EDIT-PUBLISH', 'A-POLICY.01', 'Draft edits publish exact version/content', draft, 'policy'):
            return

        file = suite.run_dir / 'delta-policy-source.mp4'
        subprocess.run([shutil.which('ffmpeg'), '-hide_banner', '-loglevel', 'error', '-f', 'lavfi', '-i',
            'testsrc2=size=320x180:rate=10', '-t', '2', '-c:v', 'libx264', '-preset', 'ultrafast', str(file)], check=True, timeout=60)
        video.update(suite.api(owner, 'post', '/videos', multipart={
            'ChannelId': suite.fixtures['channel']['channelId'], 'Title': 'Delta policy pinned decision ' + suite.run_id,
            'Visibility': 'public', 'Duration': '2', 'SourceQuality': '360p',
            'Video': {'name': file.name, 'mimeType': 'video/mp4', 'buffer': file.read_bytes()},
        }, expected=201).json())
        pending = None
        deadline = time.monotonic() + 120
        while time.monotonic() < deadline:
            queue = suite.api(admin, 'get', '/admin/moderation/queue', params={'page': 1, 'pageSize': 100}).json()
            pending = next((v for v in queue if v['videoId'] == video['videoId']), None)
            if pending:
                break
            p.wait_for_timeout(500)
        assert pending, 'Actual processing did not create moderation case'

        def pin(entry):
            path = '/admin/moderation/' + pending['moderationCaseId']
            suite.api(reviewer, 'post', path + '/claim', data={})
            result = suite.api(reviewer, 'post', path + '/resolve', data={
                'decision': 'reject', 'policyCode': code, 'reason': 'Delta pinned original version',
            }).json()
            assert result['policyCode'] == code
            def saved():
                return db.sql("SELECT policy_version FROM moderation_cases WHERE moderation_case_id=:'id'::uuid;", {'id': pending['moderationCaseId']})
            assert saved() == '1.0'
            next_policy = publish_ui(policy, '2.0', 'New policy must not replace old decision evidence')
            assert next_policy['policyId'] != policy['policyId']
            assert saved() == '1.0'
            records = [v for v in policies() if v['code'] == code]
            assert {v['version'] for v in records} == {'1.0', '2.0'}
            assert next(v for v in records if v['version'] == '1.0')['content'] == policy['content']
            assert next(v for v in suite.api(owner, 'get', '/policies').json() if v['code'] == code)['version'] == '2.0'
            p.reload()
            p.locator('.search-wrap input').fill(code)
            expect(p.locator('.data-table tbody tr').filter(has_text=code)).to_have_count(2)
            assert saved() == '1.0'
            entry['resource_ids'] = [video['videoId'], pending['moderationCaseId'], policy['policyId'], next_policy['policyId']]
            entry['steps'] = ['Independent reviewer rejects actual processed upload under published 1.0', 'Persisted moderation policy_version is exactly 1.0', 'Actual UI publishes separate 2.0 and preserves 1.0 content', 'Public API selects 2.0; original decision still references 1.0 after reload']
        case(suite, admin, 'DELTA-MODERATION-POLICY-VERSION-PINNED', 'A-POLICY.01', 'New publication cannot rewrite decision policy version', pin, 'policy')
    finally:
        if video:
            suite.api(owner, 'delete', '/videos/' + video['videoId'], expected=(204, 404))
        suite.report['cleanup'].append({'resource': 'delta policy history', 'status': 'immutable-versions-retained-as-decision-evidence', 'code': code, 'video_cleanup': 'deleted' if video else 'not-created'})
