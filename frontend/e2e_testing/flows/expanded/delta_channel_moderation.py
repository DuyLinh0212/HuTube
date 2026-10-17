"""Channel report/appeal identity links and inactive-channel decision guards."""
import shutil
import subprocess
import time
from playwright.sync_api import expect
from flows.expanded.common import case, snapshot_module
from flows.expanded.security_plan_common import identity
from support.local_db import LocalDb


def run(suite, config, actors):
    snapshot_module(suite, __file__)
    admin, reporter, reviewer = actors['admin'], actors['member'], actors['reviewer1']
    identity(suite, config, 'delta_channel_target')
    owner = suite.actor('delta-channel-target', 'user', 'delta_channel_target')
    channel = suite.api(owner, 'post', '/channels', data={
        'name': 'Delta channel cross links', 'handle': 'delta-target-' + suite.run_id[9:15],
    }, expected=201).json()
    cid = channel['channelId']
    videos, pending = [], []
    appeal = {}
    db = LocalDb(config)
    base = '/admin/reports/cases'
    try:
        file = suite.run_dir / 'delta-channel-source.mp4'
        subprocess.run([shutil.which('ffmpeg'), '-hide_banner', '-loglevel', 'error', '-f', 'lavfi', '-i',
            'testsrc2=size=640x360:rate=10', '-t', '2', '-c:v', 'libx264', '-preset', 'ultrafast', str(file)], check=True, timeout=60)
        for label in ('locked', 'deleted'):
            videos.append(suite.api(owner, 'post', '/videos', multipart={
                'ChannelId': cid, 'Title': 'Delta ' + label + ' channel decision ' + suite.run_id,
                'Visibility': 'public', 'Duration': '2', 'SourceQuality': '360p',
                'Video': {'name': file.name, 'mimeType': 'video/mp4', 'buffer': file.read_bytes()},
            }, expected=201).json()['videoId'])
        deadline = time.monotonic() + 90
        while time.monotonic() < deadline:
            rows = suite.api(admin, 'get', '/admin/moderation/queue', params={'page': 1, 'pageSize': 100}).json()
            pending = [next((v for v in rows if v['videoId'] == vid), None) for vid in videos]
            if all(pending):
                break
            owner['page'].wait_for_timeout(500)
        assert all(pending)
        for row in pending:
            suite.api(reviewer, 'post', '/admin/moderation/' + row['moderationCaseId'] + '/claim', data={})
        violation = suite.api(reporter, 'get', '/violation-types').json()[0]['violationTypeId']
        submitted = suite.api(reporter, 'post', '/reports', data={
            'targetType': 'channel', 'targetId': cid, 'violationTypeId': violation,
            'description': 'Delta channel cross link ' + suite.run_id,
        }, expected=201).json()
        report_case = next(v for v in suite.api(admin, 'get', base, params={'page': 1, 'pageSize': 100}).json()['items'] if v['targetId'] == cid)
        path = base + '/' + report_case['caseId']
        def legacy(entry):
            before = suite.api(admin, 'get', path).json()
            response = suite.api(admin, 'post', '/admin/reports/' + submitted['reportId'] + '/resolve',
                data={'decision': 'remove', 'reason': 'Legacy must reject'}, expected=409)
            assert response.json()['code'] == 'REPORT_CASE_WORKFLOW_REQUIRED'
            after = suite.api(admin, 'get', path).json()
            assert before['case']['status'] == after['case']['status'] == 'pending'
            assert before['case']['targetId'] == after['case']['targetId'] == cid
            assert suite.api(owner, 'get', '/channels/me').json()['status'] == 'active'
            suite.go(admin, '/moderation/reports', 'app-admin-reports-page', base)
            admin['page'].locator('input.report-search').fill(channel['name'])
            expect(admin['page'].locator('tbody tr').filter(has_text=channel['name'])).to_have_count(1)
            entry['resource_ids'] = [submitted['reportId'], report_case['caseId'], cid]
            entry['steps'] = ['Exact persisted report/case/channel IDs linked', 'Legacy single-report resolve returns workflow-required 409', 'Report case remains pending and channel active', 'Admin report UI still shows exact target']
        case(suite, admin, 'DELTA-LEGACY-REPORT-WORKFLOW-REJECTION', 'X-MODERATION.01', 'Legacy resolve cannot bypass grouped report workflow', legacy, 'reports')
        suite.api(admin, 'post', path + '/claim', data={})
        suite.api(admin, 'post', path + '/dispositions', data={'reportIds': [submitted['reportId']], 'disposition': 'accepted', 'reason': 'Classify owned delta report'}, expected=204)
        suite.api(admin, 'post', path + '/resolve', data={'decision': 'lock_channel', 'reason': 'Delta channel ownership/status target'})
        def crosslink(entry):
            request = {'targetType': 'channel', 'targetId': cid, 'reason': 'Delta owner cross-linked appeal', 'moderationCaseId': report_case['caseId']}
            suite.api(reporter, 'post', '/appeals', data=request, expected=403)
            suite.api(owner, 'post', '/appeals', data={**request, 'moderationCaseId': pending[0]['moderationCaseId']}, expected=400)
            assert suite.api(owner, 'get', '/channels/me').json()['status'] == 'suspended'
            suite.go(owner, '/channel/' + channel['handle'] + '/customize', 'app-channel-settings-page')
            p = owner['page']
            expect(p.locator('.channel-suspended-banner')).to_be_visible()
            p.locator('.btn-appeal-action').click()
            p.locator('#appealReasonText').fill(request['reason'])
            appeal.update(suite.response(owner, '/appeals', lambda: p.locator('.modal-appeal-dialog .modal-actions .btn-primary').click(), method='POST', status=201).json())
            assert appeal['targetId'] == cid and appeal['targetType'] == 'channel'
            assert appeal['userId'] == owner['identity']['userId'] and appeal['moderationCaseId'] == report_case['caseId']
            mine = suite.api(owner, 'get', '/appeals/my').json()
            assert next(a for a in mine if a['appealId'] == appeal['appealId'])['status'] == 'pending'
            assert not any(a['appealId'] == appeal['appealId'] for a in suite.api(reporter, 'get', '/appeals/my').json())
            p.reload()
            expect(p.locator('.channel-suspended-banner')).to_be_visible()
            suite.api(reporter, 'post', '/reports', data={'targetType': 'channel', 'targetId': cid, 'violationTypeId': violation, 'description': 'Unavailable target'}, expected=404)
            entry['resource_ids'] = [cid, report_case['caseId'], submitted['reportId'], appeal['appealId']]
            entry['steps'] = ['Foreign owner and mismatched moderation-case appeals rejected', 'Actual suspended-channel UI submits owner appeal', 'Exact report→case→channel→owner→appeal IDs agree', 'Owner pending appeal visible only in own collection; reload preserves suspended target', 'New report on suspended target rejects 404']
        case(suite, owner, 'DELTA-CHANNEL-REPORT-APPEAL-OWNER-STATUS-LINKS', 'U-CHANNEL.05', 'Channel report/appeal links enforce target status and ownership', crosslink, 'channel')
        def unavailable(entry):
            for index, status in enumerate(('suspended', 'deleted')):
                if status == 'deleted':
                    suite.api(admin, 'post', '/admin/channels/' + cid + '/unlock', data={'reason': 'Prepare owned deletion boundary'}, expected=204)
                    suite.api(owner, 'delete', '/channels/' + cid, expected=204)
                mid, vid = pending[index]['moderationCaseId'], videos[index]
                response = suite.api(reviewer, 'post', '/admin/moderation/' + mid + '/resolve', data={
                    'decision': 'approve', 'reason': 'Do not publish inactive channel',
                }, expected=409 if status == 'suspended' else 404)
                assert response.json()['code'] == ('CHANNEL_NOT_ACTIVE' if status == 'suspended' else 'CHANNEL_NOT_FOUND')
                assert db.sql("SELECT coalesce(decision,'')||'|'||coalesce(resolved_at::text,'') FROM moderation_cases WHERE moderation_case_id=:'id'::uuid;", {'id': mid}) == '|'
                suite.api(reporter, 'get', '/videos/' + vid + '/playback', expected=(403, 404))
            suite.go(admin, '/moderation/videos', 'app-admin-moderation-page', '/admin/moderation/queue')
            entry['resource_ids'] = [cid, *videos, *[v['moderationCaseId'] for v in pending]]
            entry['steps'] = ['Reviewer claims each actual pending upload before channel changes', 'Locked channel resolution rejects 409; deleted channel rejects 404', 'Exact DB cases retain no decision/resolved timestamp', 'Foreign playback denied for both targets; queue reload cannot publish deleted channel']
        case(suite, admin, 'DELTA-MODERATION-LOCKED-DELETED-CHANNEL-TARGETS', 'X-MODERATION.01', 'Channel restriction/deletion after claim cannot publish content', unavailable, 'moderation')
    finally:
        status = db.sql("SELECT status FROM channels WHERE channel_id=:'id'::uuid;", {'id': cid})
        if status == 'deleted':
            suite.api(admin, 'post', '/admin/channels/' + cid + '/restore', data={'reason': 'Cleanup owned delta target'}, expected=204)
        elif status != 'active':
            suite.api(admin, 'post', '/admin/channels/' + cid + '/unlock', data={'reason': 'Cleanup owned delta target'}, expected=204)
        if appeal:
            independent = actors['reviewer2']
            aid = '/admin/appeals/' + appeal['appealId']
            suite.api(independent, 'post', aid + '/claim', data={})
            suite.api(independent, 'post', aid + '/resolve', data={'decision': 'reject', 'reviewNote': 'Close owned delta fixture'})
        for vid in videos:
            suite.api(owner, 'delete', '/videos/' + vid, expected=(204, 404))
        suite.report['cleanup'].append({'resource': 'delta channel target', 'id': cid, 'status': 'channel-restored-videos-deleted-appeal-closed'})
        suite.release_actor(owner)
