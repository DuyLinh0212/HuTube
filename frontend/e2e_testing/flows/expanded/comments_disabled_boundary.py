"""A real uploaded, approved source with AllowComments=false rejects every actor mutation."""
import shutil
import subprocess
import time
from pathlib import Path
from playwright.sync_api import expect
from flows.expanded.common import case, snapshot_module
from support.actor_readiness import ensure_actor_pages


def run(suite, config, actors):
    snapshot_module(suite, __file__)
    ensure_actor_pages(suite, actors, ['owner', 'member', 'admin'])
    owner, member, admin = actors['owner'], actors['member'], actors['admin']
    fixture = suite.run_dir / 'comments-disabled.mp4'
    subprocess.run([shutil.which('ffmpeg'), '-hide_banner', '-loglevel', 'error', '-f', 'lavfi', '-i', 'testsrc2=size=640x360:rate=24', '-f', 'lavfi', '-i', 'sine=frequency=440:sample_rate=44100', '-t', '3', '-c:v', 'libx264', '-pix_fmt', 'yuv420p', '-c:a', 'aac', '-movflags', '+faststart', str(fixture)], check=True, timeout=90)
    channel = suite.fixtures['channel']
    video = suite.api(owner, 'post', '/videos', multipart={'channelId': channel['channelId'], 'title': 'QC disabled comments ' + suite.run_id, 'visibility': 'public', 'duration': '3', 'sourceQuality': '360p', 'allowComments': 'false', 'video': {'name': fixture.name, 'mimeType': 'video/mp4', 'buffer': fixture.read_bytes()}}, expected=201).json()
    vid = video['videoId']; endpoint = '/videos/' + vid + '/comments'
    try:
        queue = suite.api(admin, 'get', '/admin/moderation/queue', params={'page': 1, 'pageSize': 100}).json()
        pending = next(item for item in queue if item['videoId'] == vid)
        path = '/admin/moderation/' + pending['moderationCaseId']
        suite.api(admin, 'post', path + '/claim', data={})
        suite.api(admin, 'post', path + '/resolve', data={'decision': 'approve', 'reason': 'QC disabled-comments prerequisite, independent reviewer'})
        deadline = time.monotonic() + 90
        while time.monotonic() < deadline:
            current = suite.api(owner, 'get', '/videos/' + vid).json()
            if current['status'] == 'published': break
            owner['page'].wait_for_timeout(300)
        assert current['status'] == 'published'
        suite.api(member, 'get', '/videos/' + vid + '/playback')
        for key in ['owner', 'member']:
            actor = actors[key]; p = actor['page']
            def denied(entry, actor=actor, p=p):
                before = suite.api(actor, 'get', endpoint).json()
                assert before['total'] == 0
                suite.go(actor, '/watch/' + vid, 'app-watch-page')
                p.locator('textarea[name=comment]').fill('QC must never persist ' + suite.run_id)
                response = suite.response(actor, endpoint, lambda: p.locator('.comment-composer button[type=submit]').click(), method='POST', status=403)
                assert response.json()['code'] == 'COMMENTS_DISABLED'
                expect(p.locator('app-result-notice[tone=info]')).to_be_visible()
                after = suite.api(actor, 'get', endpoint).json()
                assert after['total'] == 0 and after['items'] == []
                p.reload()
                expect(p.locator('.comment-list > .comment-row')).to_have_count(0)
                entry['resource_ids'] = [vid, pending['moderationCaseId'], actor['identity']['userId']]
                entry['steps'] = ['Real FFmpeg upload with AllowComments=false is independently approved and publicly playable', 'Actual ' + actor['name'] + ' Watch composer sends request, real API returns COMMENTS_DISABLED 403', 'Bounded UI error, actual comment count remains zero and reload has no persisted comment']
            case(suite, actor, 'COMMENTS-DISABLED-' + key.upper() + '-NO-MUTATION', 'U-STUDIO.08', 'Disabled comments reject actual ' + key + ' mutation', denied, 'comments')
    finally:
        ensure_actor_pages(suite, actors, ['owner'])
        suite.api(actors['owner'], 'delete', '/videos/' + vid, expected=(200, 204))
