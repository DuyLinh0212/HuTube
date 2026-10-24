"""Missing Studio list, partial-save and late edit-response assertions only."""
import shutil
import subprocess
import time
from urllib.parse import parse_qs, urlsplit
from playwright.sync_api import expect
from flows.expanded.common import case, snapshot_module


def run(suite, config, actors):
    snapshot_module(suite, __file__)
    owner, admin, reviewer = actors['owner'], actors['admin'], actors['reviewer1']
    p = owner['page']
    cid = suite.fixtures['channel']['channelId']
    prefix = 'Delta list ' + suite.run_id[9:15]
    videos = []
    playlist = {}
    file = suite.run_dir / 'delta-studio.mp4'
    subprocess.run([shutil.which('ffmpeg'), '-hide_banner', '-loglevel', 'error', '-f', 'lavfi', '-i',
        'testsrc2=size=320x180:rate=10', '-t', '2', '-c:v', 'libx264', '-preset', 'ultrafast', str(file)], check=True, timeout=60)
    def edit(vid):
        suite.go(owner, '/studio/content/' + vid + '/edit', 'app-video-edit-page')
        expect(p.locator('#video-title')).to_be_visible()
    def load():
        return suite.go(owner, '/studio/content?channelId=' + cid, 'app-studio-content-page', '/videos/manage')
    def ids():
        return p.locator('.video-row .video-title').evaluate_all('(a)=>a.map(v=>v.pathname.split("/").pop())')
    try:
        for i in range(21):
            videos.append(suite.api(owner, 'post', '/videos', multipart={
                'ChannelId': cid, 'Title': prefix + ' ' + str(i), 'Description': 'Owned delta list dataset',
                'Visibility': 'private', 'Duration': '2', 'SourceQuality': '360p',
                'Video': {'name': file.name, 'mimeType': 'video/mp4', 'buffer': file.read_bytes()},
            }, expected=201).json()['videoId'])
        deadline = time.monotonic() + 180
        while time.monotonic() < deadline:
            values = suite.api(owner, 'get', '/videos/manage', params={'channelId': cid, 'search': prefix, 'pageSize': 100}).json()
            # Private uploads may legitimately retain processing until an
            # explicit publish transition. Collection assertions exercise the
            # real returned status rather than waiting for a fabricated one.
            if len(values['items']) == 21:
                break
            p.wait_for_timeout(1000)
        else:
            raise AssertionError('Real Studio dataset did not finish processing')

        def collection(entry):
            load()
            result = suite.response(owner, '/videos/manage', lambda: p.locator('.filter-bar input[type=search]').fill(prefix), params={'search': prefix}).json()
            assert result['total'] == 21 and len(result['items']) == 20
            expected = [v['videoId'] for v in result['items']]
            expect(p.locator('.video-row')).to_have_count(20)
            assert ids() == expected
            tail = suite.response(owner, '/videos/manage', lambda: p.locator('.load-more-sentinel').scroll_into_view_if_needed(), params={'page': '2', 'search': prefix}).json()
            assert len(tail['items']) == 1
            expected += [v['videoId'] for v in tail['items']]
            expect(p.locator('.video-row')).to_have_count(21)
            assert ids() == expected and set(expected) == set(videos)
            for kind, selector, values in (
                ('visibility', '.filter-bar select', ['private', 'public', 'unlisted']),
                ('status', '.filter-bar select', ['published', 'processing', 'blocked']),
            ):
                index = 0 if kind == 'visibility' else 1
                for value in values:
                    response = suite.response(owner, '/videos/manage', lambda value=value, index=index: p.locator(selector).nth(index).select_option(value), params={kind: value, 'page': '1'})
                    actual = response.json()
                    assert all(v[kind] == value for v in actual['items'])
                    assert actual['page'] == 1
                suite.response(owner, '/videos/manage', lambda index=index: p.locator(selector).nth(index).select_option('all'))
            empty = suite.response(owner, '/videos/manage', lambda: p.locator('.filter-bar input[type=search]').fill('NO_MATCH_' + prefix), params={'search': 'NO_MATCH_' + prefix}).json()
            assert empty['total'] == 0
            expect(p.locator('.video-row')).to_have_count(0)
            entry['category_filter_contract'] = 'N/A: Studio content currently offers visibility/status/search only; category is edited in the separate edit form.'
            entry['resource_ids'] = videos[:]
            entry['steps'] = ['21 actual encoded uploads produce exact first20/last1 with no duplicate IDs', 'Real load-more sentinel fetches page2', 'Every offered visibility/status resets page1 and filters actual data', 'Unmatched search shows no rows; category filter absent by source review']
        case(suite, owner, 'DELTA-STUDIO-CONTENT-FILTER-SEARCH-PAGINATION', 'U-STUDIO.05', 'Studio filters and pagination preserve exact owned IDs', collection, 'studio')

        # Make only one new fixture eligible for playlist UI; no historical
        # moderation/upload scenario is executed or credited by this setup.
        target = videos[0]
        suite.api(owner, 'patch', '/videos/' + target, data={'visibility': 'public'})
        queue = suite.api(admin, 'get', '/admin/moderation/queue', params={'page': 1, 'pageSize': 100}).json()
        pending = next(v for v in queue if v['videoId'] == target)
        path = '/admin/moderation/' + pending['moderationCaseId']
        suite.api(reviewer, 'post', path + '/claim', data={})
        suite.api(reviewer, 'post', path + '/resolve', data={'decision': 'approve', 'reason': 'Prepare independent delta edit fixture'})
        playlist.update(suite.api(owner, 'post', '/playlists', data={'name': 'Delta partial edit ' + suite.run_id[9:15], 'visibility': 'public'}).json())
        def thumbnail(entry):
            edit(target)
            before = suite.api(owner, 'get', '/videos/' + target).json()
            updated_title = prefix + ' thumbnail partial'
            p.locator('#video-title').fill(updated_title)
            p.locator('input[name=thumbnailMode]').first.check()
            pattern = '**/api/v1/videos/' + target + '/thumbnail'
            aborted = []
            def abort(route):
                aborted.append(True)
                route.abort('failed')
            p.route(pattern, abort)
            try:
                suite.response(owner, '/videos/' + target, lambda: p.locator('.header-actions .button-primary').click(), method='PATCH')
                expect(p.locator('.notice-error')).to_be_visible()
                expect(p.locator('.notice-success')).to_have_count(0)
                assert aborted
            finally:
                p.unroute(pattern, abort)
            after = suite.api(owner, 'get', '/videos/' + target).json()
            assert after['title'] == updated_title and after['thumbnailUrl'] == before['thumbnailUrl']
            p.reload()
            expect(p.locator('#video-title')).to_have_value(updated_title)
            entry['resource_ids'] = [target]
            entry['steps'] = ['Real metadata PATCH commits, then thumbnail transport alone fails', 'Actual UI shows error and no complete-save success', 'API preserves old thumbnail with new committed metadata', 'Reload retains partial saved title']
        case(suite, owner, 'DELTA-STUDIO-THUMBNAIL-PARTIAL-FAILURE', 'U-STUDIO.05', 'Thumbnail failure never produces full-save success', thumbnail, 'studio')
        def playlist_failure(entry):
            edit(target)
            p.locator('#video-title').fill(prefix + ' playlist partial')
            row = p.locator('.playlist-choice').filter(has_text=playlist['name'])
            row.locator('input[type=checkbox]').check()
            pattern = '**/api/v1/playlists/' + playlist['playlistId'] + '/videos'
            aborted = []
            def abort(route):
                aborted.append(True)
                route.abort('failed')
            p.route(pattern, abort)
            try:
                suite.response(owner, '/videos/' + target, lambda: p.locator('.header-actions .button-primary').click(), method='PATCH')
                expect(p.locator('.notice-error')).to_be_visible()
                expect(p.locator('.notice-success')).to_have_count(0)
                assert aborted
            finally:
                p.unroute(pattern, abort)
            assert suite.api(owner, 'get', '/videos/' + target).json()['title'] == prefix + ' playlist partial'
            assert not any(v['videoId'] == target for v in suite.api(owner, 'get', '/playlists/' + playlist['playlistId']).json()['items'])
            p.reload()
            expect(p.locator('#video-title')).to_have_value(prefix + ' playlist partial')
            entry['resource_ids'] = [target, playlist['playlistId']]
            entry['steps'] = ['Metadata commits then exact selected playlist transport fails', 'Partial error visible; full success absent', 'Reload/API retain edited metadata with zero unintended playlist membership']
        case(suite, owner, 'DELTA-STUDIO-PLAYLIST-PARTIAL-FAILURE', 'U-STUDIO.05', 'Playlist failure leaves honest partial-save state', playlist_failure, 'studio')
        def late(entry):
            edit(target)
            p.locator('#video-title').fill(prefix + ' late first save')
            held = []
            pattern = '**/api/v1/videos/' + target
            def delay(route):
                if route.request.method == 'PATCH':
                    held.append((route, route.fetch()))
                else:
                    route.continue_()
            p.route(pattern, delay)
            try:
                p.locator('.header-actions .button-primary').click()
                expect(p.locator('.header-actions .button-primary')).to_be_disabled()
                p.locator('.header-actions .button-quiet').click()
                expect(p.locator('app-studio-content-page')).to_be_visible()
                link = p.locator('a.action-edit[href="/studio/content/' + videos[1] + '/edit"]')
                # The new fixtures sort first; the second target is on page1.
                link.click()
                expected = suite.api(owner, 'get', '/videos/' + videos[1]).json()['title']
                expect(p.locator('#video-title')).to_have_value(expected)
                assert held
                route, response = held.pop()
                route.fulfill(response=response)
                p.wait_for_timeout(200)
                expect(p.locator('#video-title')).to_have_value(expected)
                assert suite.api(owner, 'get', '/videos/' + videos[1]).json()['title'] == expected
                entry['resource_ids'] = [target, videos[1]]
                entry['steps'] = ['Hold genuine first metadata-save response after server commit', 'Navigate through real Back to content and open different video', 'Release original response after second form loads', 'Second form/resource remains unchanged by late first save']
            finally:
                for route, response in held:
                    route.fulfill(response=response)
                p.unroute(pattern, delay)
        case(suite, owner, 'DELTA-STUDIO-EDIT-LATE-RESPONSE-TARGET', 'U-STUDIO.05', 'Late previous save cannot replace another edit target', late, 'studio')
    finally:
        if playlist:
            suite.api(owner, 'delete', '/playlists/' + playlist['playlistId'], expected=(204, 404))
        for vid in videos:
            suite.api(owner, 'delete', '/videos/' + vid, expected=(204, 404))
        suite.report['cleanup'].append({'resource': 'delta studio dataset', 'ids': videos, 'status': 'videos-and-playlist-deleted'})
