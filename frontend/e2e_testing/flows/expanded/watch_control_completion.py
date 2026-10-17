"""Missing player assertions use decoded media properties, never just icons."""
from playwright.sync_api import expect
from flows.expanded.common import case, snapshot_module


def run(suite, config, actors):
    snapshot_module(suite, __file__)
    owner, member = actors['owner'], actors['member']
    videos = suite.api(owner, 'get', '/videos/manage', params={'channelId': suite.fixtures['channel']['channelId'], 'pageSize': 100}).json()['items']
    selected = max((v for v in videos if v['status'] == 'published' and v['moderationStatus'] == 'approved' and v['visibility'] == 'public'), key=lambda v: v['duration'])
    vid = selected['videoId']
    original = suite.api(owner, 'get', '/videos/' + vid).json()
    assert original['duration'] >= 2
    second = min(10, original['duration'] // 2)
    chapters = [{'startSeconds': 0, 'title': 'QC bắt đầu'}, {'startSeconds': second, 'title': 'QC chương hai'}]
    suite.api(owner, 'patch', '/videos/' + vid, data={'chapters': chapters})
    p = member['page']
    try:
        def controls(entry):
            suite.go(member, '/watch/' + vid, 'app-watch-page')
            p.wait_for_function('()=>document.querySelector("video.video-player")?.readyState>=2')
            video = p.locator('video.video-player')
            video.hover()
            toggle = p.locator('.player-control-group').first.locator('button').first
            if video.evaluate('(v)=>!v.paused'): toggle.click()
            p.wait_for_function('()=>document.querySelector("video.video-player").paused')
            suite.evidence(member, entry, 'actual-paused')
            toggle.click()
            p.wait_for_function('()=>!document.querySelector("video.video-player").paused')
            video.hover(); toggle.click()
            p.wait_for_function('()=>document.querySelector("video.video-player").paused')
            p.locator('.player-progress').fill(str(second))
            p.wait_for_function('(time)=>Math.abs(document.querySelector("video.video-player").currentTime-time)<.4', arg=second)
            for value in ['0', '0.5', '1']:
                p.locator('.player-volume').fill(value)
                p.wait_for_function('(value)=>Math.abs(document.querySelector("video.video-player").volume-value)<.01', arg=float(value))
            for _ in range(2):
                before = video.evaluate('(v)=>v.muted')
                p.locator('.player-volume-button').click()
                assert video.evaluate('(v)=>v.muted') != before
            speed = p.locator('.player-speed-option select')
            for option in speed.locator('option').all():
                value = option.get_attribute('value')
                expected = float(option.inner_text().replace('×', '').strip())
                speed.select_option(value)
                assert video.evaluate('(v)=>v.playbackRate') == expected
            suite.evidence(member, entry, 'volume-speed-actual-properties')
            p.locator('.chapter-row').nth(0).click()
            p.wait_for_function('()=>document.querySelector("video.video-player").currentTime<.4')
            p.locator('.chapter-row').nth(1).click()
            p.wait_for_function('(time)=>Math.abs(document.querySelector("video.video-player").currentTime-time)<.4', arg=second)
            expect(p.locator('.chapter-row').nth(1)).to_contain_text(chapters[1]['title'])
            assert video.evaluate('(v)=>v.videoWidth>0 && Number.isFinite(v.duration)')
            entry['resource_ids'] = [vid]
            entry['steps'] = ['Actual decoded approved source: click play/pause and assert paused properties', 'Seek actual progress control; currentTime reaches requested second', 'Volume 0/.5/1 and mute/unmute match media element properties', 'Every offered speed sets exact playbackRate', 'Each actual chapter seeks its persisted startSeconds and retains decoded source']
        case(suite, member, 'WATCH-PLAY-PAUSE-SEEK-VOLUME-SPEED-CHAPTER', 'U-WATCH.01', 'Player controls change actual decoded playback state', controls, 'watch')
    finally:
        suite.api(owner, 'patch', '/videos/' + vid, data={'chapters': original['chapters']})
