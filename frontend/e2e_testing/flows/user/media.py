"""Real FFmpeg fixture -> UI upload -> owner playback; no metadata-only seed."""
from pathlib import Path
import shutil
import subprocess
import time
from urllib.parse import urlsplit

from playwright.sync_api import expect


def run(suite, owner, member):
    page = owner['page']
    fixture = Path(suite.config['state_dir']) / suite.state.get('fixture_name','web-fixture.mp4')
    fixture_seconds = suite.state.get('fixture_seconds',10)
    ffmpeg = shutil.which('ffmpeg')
    if not ffmpeg:
        suite.blocked(owner, 'U-STUDIO-UPLOAD-01', 'Upload video fixture thật', 'FFmpeg executable missing')
        return
    if not fixture.exists():
        subprocess.run([ffmpeg, '-hide_banner', '-loglevel', 'error', '-f','lavfi','-i','testsrc2=size=640x360:rate=24','-f','lavfi','-i','sine=frequency=440:sample_rate=44100','-t',str(fixture_seconds),'-c:v','libx264','-pix_fmt','yuv420p','-c:a','aac','-movflags','+faststart',str(fixture)],check=True,timeout=120)
    video = {}
    def upload():
        expected_title = suite.state.get('video_title','HuTube E2E — Mẫu hình và âm thanh kiểm thử')
        existing_id = suite.state.get('video_id')
        if existing_id:
            existing = suite.api(owner, 'get', '/videos/' + existing_id)
            if existing.status == 200 and existing.json().get('title') == expected_title:
                video.update(existing.json())
                suite.go(owner, '/watch/' + existing_id, 'app-watch-page')
                return 'reused'
            assert existing.status in (200, 404)
        suite.go(owner, '/studio/upload', 'app-video-upload-wizard')
        page.locator('.btn-wizard-next').click()
        expect(page.locator('[role=alert]')).to_be_visible()
        if hasattr(suite,'evidence'): suite.evidence(owner,'step1-required')
        page.locator('#videoFile').set_input_files(str(fixture))
        expect(page.locator('.file-name')).to_have_text(fixture.name)
        # The wizard auto-advances when browser metadata and quota preflight succeed.
        # Wait for the details form instead of looking for the step-1 readiness label.
        expect(page.locator('#videoTitle')).to_be_visible(timeout=45000)
        if hasattr(suite,'evidence'): suite.evidence(owner,'step1-file-ready')
        page.locator('#videoTitle').fill('')
        page.locator('.btn-wizard-next').click()
        expect(page.locator('#videoTitle')).to_be_visible()
        page.locator('#videoTitle').fill(suite.state.get('video_title','HuTube E2E — Mẫu hình và âm thanh kiểm thử'))
        page.locator('#videoDesc').fill('Video sinh bằng FFmpeg: 640×360, 10 giây, âm thanh 440 Hz. Dữ liệu kỹ thuật dành riêng cho E2E.')
        if hasattr(suite,'evidence'): suite.evidence(owner,'step2-metadata')
        for step in range(3):
            page.locator('.btn-wizard-next').click()
            if hasattr(suite,'evidence'): suite.evidence(owner,'step'+str(step+3))
        expect(page.locator('.schedule-section-card')).to_have_count(0)
        expect(page.locator('input[name=publishMode]')).to_have_count(0)
        page.locator('input[name=visibility][value=private]').check()
        upload_sessions_path = urlsplit(suite.config['api_url']).path.rstrip('/') + '/videos/upload-sessions/'
        def is_upload_complete(response):
            path = urlsplit(response.url).path.rstrip('/')
            return (response.request.method == 'POST' and path.startswith(upload_sessions_path)
                    and path.endswith('/complete'))

        with page.expect_response(is_upload_complete, timeout=120000) as response:
            page.locator('.btn-wizard-publish').click()
        accepted = response.value
        assert accepted.status == 202
        assert accepted.json()['status'] == 'processing'
        assert 'respond-async' in accepted.request.headers.get('prefer', '')
        status_path = urlsplit(accepted.url).path.removesuffix('/complete')
        # The real wizard polls its upload session. Require both its terminal
        # HTTP response and completed UI; acceptance alone is not an upload.
        with page.expect_response(lambda result: result.request.method == 'GET'
                                  and urlsplit(result.url).path == status_path
                                  and result.status == 200, timeout=120000) as completed:
            expect(page.locator('.step-6')).to_be_visible(timeout=120000)
        video.update(completed.value.json())
        assert video['videoId'] and video['visibility'] == 'private'
        assert video['title'] == expected_title
        suite.state['video_id'] = video['videoId']; suite.save()
    suite.case(owner, 'U-STUDIO-UPLOAD-01', 'Upload video thật qua wizard; required và không hiện lịch đăng chưa hỗ trợ', upload,
               expected='POST 202 nhận xử lý nền; GET 200 và UI hoàn tất trả đúng video private; checkpoint ID, không tạo lại khi retry', data='FFmpeg 10s 640x360 + sine 440Hz')
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
        page.bring_to_front()
        page.wait_for_function('()=>document.visibilityState==="visible"')
        player = page.locator('video').first
        expect(player).to_be_visible()
        page.wait_for_function('() => { const v=document.querySelector("video"); return v && v.readyState>=1 && v.duration>0; }', timeout=45000)
        duration = player.evaluate('(v) => v.duration')
        assert fixture_seconds-1 <= duration <= fixture_seconds+1
        assert player.evaluate('(v)=>v.videoWidth>0 && v.videoHeight>0'), 'Decoded video dimensions missing'
        page.locator('.player-volume-button').click()
        # Native autoplay can settle after metadata or a volume interaction.
        # Establish a paused state, then exercise the stable UI play control.
        player.hover()
        playback_button=page.locator('.player-control-group').first.locator('button').first
        if not player.evaluate('(v) => v.paused'):
            playback_button.click()
        page.wait_for_function('()=>document.querySelector("video").paused')
        playback_button.click()
        suite.state['playback_activation']=page.evaluate('()=>{const v=document.querySelector("video");return {visibility:document.visibilityState,focused:document.hasFocus(),userActivation:navigator.userActivation.isActive,paused:v.paused,readyState:v.readyState,mediaError:v.error?.code??null}}')
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
        if page.viewport_size and page.viewport_size['width'] <= 620:
            expect(page.locator('.player-volume')).to_be_hidden()
            was_muted=player.evaluate('(v)=>v.muted')
            page.locator('.player-volume-button').click()
            assert player.evaluate('(v)=>v.muted') != was_muted
            page.locator('.player-volume-button').click()
            assert player.evaluate('(v)=>v.muted') == was_muted
            suite.state['audio_control_branch']='Mobile layout hides volume range; actual mute/unmute toggles native muted state and restores it'
        else:
            page.locator('.player-volume').fill('0.5')
            assert abs(player.evaluate('(v) => v.volume') - 0.5) < 0.01
            suite.state['audio_control_branch']='Visible volume range changes native volume to 0.5'
    suite.case(owner, 'U-WATCH-PLAYBACK-01', 'Transcode và phát video có frame/âm thanh thật', playback,
               expected='Có rendition; duration ~10s; UI play/pause/seek/speed/volume thay đổi trạng thái video thật')

    def private_access():
        response = suite.api(member, 'get', '/videos/' + video['videoId'] + '/playback')
        assert response.status in (403, 404)
    suite.case(member, 'U-WATCH-PRIVATE-01', 'Member không lấy được playback video private', private_access,
               expected='403/404, không cấp stream riêng tư')
