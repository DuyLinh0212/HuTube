"""Real progress/reload/retry must not count duplicate sessions or sum repeated checkpoints."""
import time
from urllib.parse import urlsplit, parse_qs
from playwright.sync_api import expect
from flows.expanded.common import case, snapshot_module
from tests.full_functional import pickup_link
from support.local_db import LocalDb


def run(suite, config, actors):
    snapshot_module(suite, __file__)
    stamp = str(time.time_ns()); key = 'view_session'
    credentials = {'email': 'qc.view.' + stamp + '@example.test', 'username': 'qc_vw_' + stamp, 'password': 'QCFixturePassword2026!'}
    suite.credentials[key] = credentials
    setup = suite.actor('view-session-setup', 'user', 'guest'); setup['api_url'] = config['api_url']; sent = time.time()
    suite.api(setup, 'post', '/auth/register', data={**credentials, 'displayName': 'QC view boundary'}, expected=201)
    token = parse_qs(urlsplit(pickup_link(config, credentials['email'], 'verify-email', sent)).query)['token'][0]
    suite.api(setup, 'post', '/auth/verify-email', data={'token': token}); suite.release_actor(setup)
    viewer = suite.actor('view-session-viewer', 'user', key); p = viewer['page']; uid = viewer['identity']['userId']
    vid = suite.fixtures['video']['videoId']; db = LocalDb(config)
    def count():
        return int(db.sql("SELECT count(*) FROM viewing_histories WHERE user_id=:'uid'::uuid AND video_id=:'vid'::uuid;", {'uid': uid, 'vid': vid}))
    try:
        def boundary(entry):
            baseline = suite.api(viewer, 'get', '/videos/' + vid).json()['stats']; assert count() == 0
            endpoint = '/videos/' + vid + '/watch-progress'
            for seconds in [2, 2, 3]:
                suite.api(viewer, 'put', endpoint, data={'watchedSeconds': seconds})
                assert count() == 1
                stats = suite.api(viewer, 'get', '/videos/' + vid).json()['stats']
                assert stats['views'] == baseline['views'] + 1 and stats['watchSeconds'] == baseline['watchSeconds'] + seconds
            clamped = suite.api(viewer, 'put', endpoint, data={'watchedSeconds': -1}).json()
            assert clamped['watchedSeconds'] == 0 and clamped['progress'] == 0
            assert count() == 1
            for minutes, expected in [(29, 1), (31, 2)]:
                db.sql("UPDATE viewing_histories SET viewed_at=now()-(:'minutes'||' minutes')::interval WHERE user_id=:'uid'::uuid AND video_id=:'vid'::uuid;", {'uid': uid, 'vid': vid, 'minutes': str(minutes)})
                suite.api(viewer, 'put', endpoint, data={'watchedSeconds': 2})
                assert count() == expected
            stats = suite.api(viewer, 'get', '/videos/' + vid).json()['stats']
            assert stats['views'] == baseline['views'] + 2 and stats['watchSeconds'] == baseline['watchSeconds'] + 4
            for action in [lambda: suite.go(viewer, '/watch/' + vid, 'app-watch-page'), lambda: p.reload()]:
                action(); p.wait_for_function('()=>document.querySelector("video.video-player")?.readyState>=2')
                video = p.locator('video.video-player')
                if video.evaluate('(v)=>!v.paused'):
                    video.hover(); p.locator('.player-control-group').first.locator('button').first.click()
                assert count() == 2
                actual = suite.api(viewer, 'get', '/videos/' + vid).json()['stats']
                assert actual['views'] == stats['views'] and actual['watchSeconds'] == stats['watchSeconds']
            entry['resource_ids'] = [vid, uid]
            entry['storage_assertion'] = 'Only this newly registered viewer viewing-history timestamps are shifted around server cooldown; row creation/count/checkpoints are produced by actual API requests.'
            entry['steps'] = ['Fresh independent viewer has zero rows for the real approved source', 'Actual repeated checkpoints replace watch duration without adding sessions or summing duplicate seconds', 'Negative progress clamps to zero without new rows', 'Shift only owned checkpoint time to 29/31 minutes; actual API reuses before and creates after cooldown', 'Actual decoded Watch and reload are paused through UI, preserve view/watchSeconds counts and cannot double count', 'Exact before/at/after 30-minute precision is checked by dedicated fake-clock unit tests']
        case(suite, viewer, 'WATCH-PROGRESS-SESSION-COOLDOWN-RELOAD', 'U-WATCH.02', 'Repeated progress and reload preserve exact counted sessions', boundary, 'watch')
    finally:
        suite.go(viewer, '/account', 'app-account-page', '/account/profile')
        suite.api(viewer, 'delete', '/library/history/' + vid, expected=204)
        suite.release_actor(viewer)
