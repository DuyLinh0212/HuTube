"""Real FFmpeg fixture -> UI upload -> owner playback; no metadata-only seed."""
from pathlib import Path
import shutil
import subprocess
import time

from playwright.sync_api import expect


def run(suite, owner, member):
    page = owner['page']
    fixture = Path(suite.config['state_dir']) / 'web-fixture.mp4'
    ffmpeg = shutil.which('ffmpeg')
    if not ffmpeg:
        suite.blocked(owner, 'U-STUDIO-UPLOAD-01', 'Upload video fixture thật', 'FFmpeg executable missing')
        return
    if not fixture.exists():
        subprocess.run([ffmpeg, '-hide_banner', '-loglevel', 'error', '-f', 'lavfi', '-i', 'testsrc2=size=640x360:rate=24', '-f', 'lavfi', '-i', 'sine=frequency=440:sample_rate=44100', '-t', '10', '-c:v', 'libx264', '-pix_fmt', 'yuv420p', '-c:a', 'aac', '-movflags', '+faststart', str(fixture)], check=True, timeout=120)
    video = {}
    def upload():
        existing_id = suite.state.get('video_id')
        if existing_id:
            existing = suite.api(owner, 'get', '/videos/' + existing_id)
            if existing.status == 200:
                video.update(existing.json())
                suite.go(owner, '/watch/' + existing_id, 'app-watch-page')
                return 'reused'
            assert existing.status == 404
        suite.go(owner, '/studio/upload', 'app-video-upload-wizard')
        page.locator('.btn-wizard-next').click()
        expect(page.locator('[role=alert]')).to_be_visible()
        page.locator('#videoFile').set_input_files(str(fixture))
        expect(page.locator('.file-name')).to_have_text(fixture.name)
        # Browser metadata and quota preflight are asynchronous, finite states.
        expect(page.locator('.progress-bar-labels')).to_contain_text('Sẵn sàng', timeout=45000)
        page.locator('.btn-wizard-next').click()
        expect(page.locator('#videoTitle')).to_be_visible()
        page.locator('#videoTitle').fill('')
        page.locator('.btn-wizard-next').click()
        expect(page.locator('#videoTitle')).to_be_visible()
        page.locator('#videoTitle').fill('HuTube E2E — Mẫu hình và âm thanh kiểm thử')
        page.locator('#videoDesc').fill('Video sinh bằng FFmpeg: 640×360, 10 giây, âm thanh 440 Hz. Dữ liệu kỹ thuật dành riêng cho E2E.')
        for _ in range(3):
            page.locator('.btn-wizard-next').click()
        expect(page.locator('input[name=publishMode][value=schedule]')).to_be_disabled()
        page.locator('input[name=visibility][value=private]').check()
        with page.expect_response(lambda r: r.request.method == 'POST' and r.url == suite.config['api_url'] + '/videos', timeout=120000) as response:
            page.locator('.btn-wizard-publish').click()
        assert response.value.status == 201
        video.update(response.value.json())
        suite.state['video_id'] = video['videoId']; suite.save()
        expect(page.locator('.step-6')).to_be_visible(timeout=120000)
    suite.case(owner, 'U-STUDIO-UPLOAD-01', 'Upload video thật qua wizard; required và schedule disabled', upload,
               expected='UI POST multipart 201; checkpoint video ID; không tạo lại khi retry', data='FFmpeg 10s 640x360 + sine 440Hz')
    if not video:
        suite.blocked(owner, 'U-WATCH-PLAYBACK-01', 'Playback fixture đã upload', 'Upload did not produce a video ID')
        return

    def playback():
        deadline = time.monotonic() + 180
        while time.monotonic() < deadline:
            response = suite.api(owner, 'get', '/videos/' + video['videoId'] + '/playback')
            if response.status == 200 and response.json().get('renditions'):
                break
            assert response.status in (200, 409, 422, 503), 'Playback polling HTTP ' + str(response.status)
            page.wait_for_timeout(2000)
        else:
            raise TimeoutError('Transcoding did not produce playback in 180s')
        suite.go(owner, '/watch/' + video['videoId'], 'app-watch-page')
        player = page.locator('video').first
        expect(player).to_be_visible()
        page.wait_for_function('() => { const v=document.querySelector("video"); return v && v.readyState>=1 && v.duration>0; }', timeout=45000)
        duration = player.evaluate('(v) => v.duration')
        assert 9 <= duration <= 11
        if not player.evaluate('(v) => v.paused'):
            page.locator('.player-control-group').first.locator('button').first.click()
        page.locator('.player-volume-button').click()
        page.locator('.player-big-play').click()
        page.wait_for_function('() => document.querySelector("video").currentTime > 1', timeout=15000)
        player.hover()
        page.locator('.player-control-group').first.locator('button').first.click()
        assert player.evaluate('(v) => v.paused')
        page.locator('.player-progress').fill('5')
        page.wait_for_function('() => Math.abs(document.querySelector("video").currentTime-5)<0.5')
        speed = page.locator('.player-option select').nth(1)
        speed.select_option(label='1.5×')
        assert player.evaluate('(v) => v.playbackRate') == 1.5
        speed.select_option(label='1×')
        page.locator('.player-volume').fill('0.5')
        assert abs(player.evaluate('(v) => v.volume') - 0.5) < 0.01
    suite.case(owner, 'U-WATCH-PLAYBACK-01', 'Transcode và phát video có frame/âm thanh thật', playback,
               expected='Có rendition; duration ~10s; UI play/pause/seek/speed/volume thay đổi trạng thái video thật')

    def private_access():
        response = suite.api(member, 'get', '/videos/' + video['videoId'] + '/playback')
        assert response.status in (403, 404)
    suite.case(member, 'U-WATCH-PRIVATE-01', 'Member không lấy được playback video private', private_access,
               expected='403/404, không cấp stream riêng tư')
