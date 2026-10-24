"""Owned API fixture setup, never counted as new functional PASS executions."""
import shutil
import subprocess
import time
from urllib.parse import urlsplit, parse_qs
from tests.full_functional import pickup_link


def prepare(suite, config, admin):
    stamp = str(time.time_ns())
    owner = suite.actor('privacy-fixture-owner-' + stamp, 'user', 'guest')
    owner['api_url'] = config['api_url']
    owner['headers'].update({'X-HuTube-Client': 'web', 'Origin': owner['origin']})
    credentials = {'email': 'qc.privacy.' + stamp + '@example.test', 'username': 'qc_pv_' + stamp, 'password': 'QCFixturePassword2026!'}
    sent = time.time()
    suite.api(owner, 'post', '/auth/register', data={**credentials, 'displayName': 'QC privacy owner'}, expected=201)
    token = parse_qs(urlsplit(pickup_link(config, credentials['email'], 'verify-email', sent)).query)['token'][0]
    suite.api(owner, 'post', '/auth/verify-email', data={'token': token})
    login = suite.api(owner, 'post', '/auth/login', data=credentials).json()
    owner['headers']['Authorization'] = 'Bearer ' + login['accessToken']; owner['identity'] = login['user']
    channel = suite.api(owner, 'post', '/channels', data={'name': 'QC privacy ' + stamp, 'handle': 'qc-privacy-' + stamp}, expected=201).json()
    path = suite.run_dir / 'privacy-fixture.mp4'
    subprocess.run([shutil.which('ffmpeg'), '-hide_banner', '-loglevel', 'error', '-f', 'lavfi', '-i', 'testsrc2=size=640x360:rate=24', '-f', 'lavfi', '-i', 'sine=frequency=440:sample_rate=44100', '-t', '3', '-c:v', 'libx264', '-pix_fmt', 'yuv420p', '-c:a', 'aac', '-movflags', '+faststart', str(path)], check=True, timeout=90)
    video = suite.api(owner, 'post', '/videos', multipart={'channelId': channel['channelId'], 'title': 'QC privacy ' + stamp, 'visibility': 'public', 'duration': '3', 'sourceQuality': '360p', 'video': {'name': path.name, 'mimeType': 'video/mp4', 'buffer': path.read_bytes()}}, expected=201).json()
    queue = suite.api(admin, 'get', '/admin/moderation/queue', params={'pageSize': 100}).json()
    pending = next(item for item in queue if item['videoId'] == video['videoId'])
    endpoint = '/admin/moderation/' + pending['moderationCaseId']
    suite.api(admin, 'post', endpoint + '/claim', data={})
    suite.api(admin, 'post', endpoint + '/resolve', data={'decision': 'approve', 'reason': 'QC independent approval for privacy matrix prerequisite'})
    deadline = time.monotonic() + 90
    while time.monotonic() < deadline:
        video = suite.api(owner, 'get', '/videos/' + video['videoId']).json()
        if video['status'] == 'published': break
        owner['page'].wait_for_timeout(300)
    assert video['status'] == 'published'
    suite.report['setup'].append({'resource': 'independent owned approved public source', 'channel_id': channel['channelId'], 'video_id': video['videoId'], 'moderation_id': pending['moderationCaseId'], 'status': 'prepared through actual registration/upload/approval, not a newly counted PASS'})
    return owner, channel, video
