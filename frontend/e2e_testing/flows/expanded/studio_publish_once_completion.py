"""Prove a rapid real publish gesture creates one response-owned video ID."""
import shutil
import subprocess

from playwright.sync_api import expect

from flows.expanded.common import case, snapshot_module


def run(suite, config, actors):
    snapshot_module(suite, __file__)
    owner = actors['owner']
    page = owner['page']
    channel_id = suite.fixtures['channel']['channelId']
    fixture = suite.run_dir / 'publish-once-fixture.mp4'
    subprocess.run([
        shutil.which('ffmpeg'), '-hide_banner', '-loglevel', 'error',
        '-f', 'lavfi', '-i', 'testsrc2=size=640x360:rate=24', '-t', '8',
        '-c:v', 'libx264', '-pix_fmt', 'yuv420p', str(fixture),
    ], check=True, timeout=60)
    created = {}

    def publish_once(entry):
        title = 'QC publish once ' + suite.run_id
        requests = []
        def record(request):
            if request.method == 'POST' and request.url == owner['api_url'] + '/videos':
                requests.append(request.headers.get('idempotency-key'))
        page.on('request', record)
        try:
            suite.go(owner, '/studio/upload?channelId=' + channel_id, 'app-video-upload-wizard')
            page.locator('#videoFile').set_input_files(str(fixture))
            expect(page.locator('.btn-wizard-next')).to_be_enabled(timeout=45000)
            page.locator('.btn-wizard-next').click()
            page.locator('#videoTitle').fill(title)
            for _ in range(3):
                page.locator('.btn-wizard-next').click()
            expect(page.locator('.step-5')).to_be_visible()
            page.locator('input[name=visibility][value=private]').check()
            publish = page.locator('.btn-wizard-publish')
            box = publish.bounding_box()
            assert box
            with page.expect_response(lambda response: response.request.method == 'POST' and response.url == owner['api_url'] + '/videos', timeout=45000) as pending:
                # Two physical pointer clicks hit the real button location.  The
                # first disables it synchronously; the second must not enqueue a
                # second accepted upload request.
                page.mouse.click(box['x'] + box['width'] / 2, box['y'] + box['height'] / 2)
                page.mouse.click(box['x'] + box['width'] / 2, box['y'] + box['height'] / 2)
            response = pending.value
            assert response.status == 201
            created.update(response.json())
            expect(page.locator('app-upload-progress-tray .upload-tray')).to_be_visible()
            expect(page.locator('.step-6')).to_be_visible(timeout=45000)
            assert len(requests) == 1 and requests[0], 'Rapid publish emitted more than one accepted upload request'
            stored = suite.api(owner, 'get', '/videos/manage', params={
                'channelId': channel_id, 'search': title, 'page': 1, 'pageSize': 100,
            }).json()['items']
            exact = [item for item in stored if item['title'] == title]
            assert len(exact) == 1 and exact[0]['videoId'] == created['videoId']
            entry['resource_ids'] = [channel_id, created['videoId']]
            entry['steps'] = [
                'Prepare a real MP4 through the five visible wizard steps and choose private visibility',
                'Send two rapid physical pointer clicks to Publish; one real POST returns 201 with the server video ID',
                'The upload tray becomes visible, completion step renders, and real managed inventory contains exactly that one ID',
            ]
        finally:
            page.remove_listener('request', record)

    try:
        case(suite, owner, 'UPLOAD-PUBLISH-RAPID-ONE-RESPONSE-ID', 'U-STUDIO.03',
             'Rapid publish gesture creates one response-owned video', publish_once, 'studio')
    finally:
        if created.get('videoId'):
            suite.api(owner, 'delete', '/videos/' + created['videoId'], expected=(200, 204))
