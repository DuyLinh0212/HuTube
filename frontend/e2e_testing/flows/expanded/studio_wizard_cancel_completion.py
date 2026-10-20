"""Isolated cancel branch for the upload wizard; no publishing or prior-case replay."""
import shutil
import subprocess

from playwright.sync_api import expect

from flows.expanded.common import case, snapshot_module


def run(suite, config, actors):
    snapshot_module(suite, __file__)
    owner = actors['owner']
    page = owner['page']
    channel_id = suite.fixtures['channel']['channelId']
    fixture = suite.run_dir / 'wizard-cancel-fixture.mp4'
    subprocess.run([
        shutil.which('ffmpeg'), '-hide_banner', '-loglevel', 'error',
        '-f', 'lavfi', '-i', 'testsrc2=size=640x360:rate=24', '-t', '8',
        '-c:v', 'libx264', '-pix_fmt', 'yuv420p', str(fixture),
    ], check=True, timeout=60)

    def cancel_selected_file(entry):
        before = suite.api(owner, 'get', '/videos/manage', params={
            'channelId': channel_id, 'page': 1, 'pageSize': 100,
        }).json()
        before_ids = {item['videoId'] for item in before['items']}
        posts = []
        def record(request):
            if request.method == 'POST' and request.url == owner['api_url'] + '/videos':
                posts.append(request)
        page.on('request', record)
        try:
            suite.go(owner, '/studio/upload?channelId=' + channel_id, 'app-video-upload-wizard')
            page.locator('#videoFile').set_input_files(str(fixture))
            expect(page.locator('.file-name')).to_be_visible()
            expect(page.locator('.btn-wizard-next')).to_be_enabled(timeout=45000)
            page.locator('.btn-cancel-upload').click()
            expect(page.locator('.file-name')).to_have_count(0)
            expect(page.locator('.btn-cancel-upload')).to_have_count(0)
            assert not posts, 'Selecting and cancelling a local file issued an upload POST'
            after = suite.api(owner, 'get', '/videos/manage', params={
                'channelId': channel_id, 'page': 1, 'pageSize': 100,
            }).json()
            assert {item['videoId'] for item in after['items']} == before_ids
            entry['resource_ids'] = [channel_id]
            entry['steps'] = [
                'Read the actual owned video IDs before selecting a real MP4',
                'Wait for browser metadata/preflight readiness, then use the visible Cancel selected-file control',
                'File controls disappear; no POST /videos is emitted and the actual owned inventory remains identical',
            ]
        finally:
            page.remove_listener('request', record)

    case(suite, owner, 'UPLOAD-WIZARD-CANCEL-SELECTED-NO-MUTATION', 'U-STUDIO.02',
         'Cancelling a selected local video clears wizard state without upload mutation',
         cancel_selected_file, 'studio')
