"""Missing Admin video category/stats, stale-target and permission assertions."""
from urllib.parse import parse_qs, urlsplit
from playwright.sync_api import expect
from flows.expanded.common import case, snapshot_module
from support.live_suite import PrerequisiteMissing


def run(suite, config, actors):
    snapshot_module(suite, __file__)
    admin, reviewer = actors['admin'], actors['reviewer1']
    p = admin['page']
    def load(actor=admin):
        return suite.go(actor, '/videos', 'app-admin-videos-page', '/admin/videos')

    def collection(entry):
        created = suite.api(admin, 'post', '/admin/topics', data={
            'name': 'Delta video category ' + suite.run_id[9:15],
            'slug': 'delta-video-category-' + suite.run_id[9:15], 'description': 'Owned category filter fixture',
        }, expected=201).json()
        data = load()
        categories = suite.api(admin, 'get', '/categories').json()
        checks = []
        for index, category in enumerate(categories):
            component = p.locator('app-custom-select').first
            component.get_by_role('combobox').click()
            response = suite.response(admin, '/admin/videos', lambda: component.get_by_role('option').nth(index + 1).click())
            result = response.json()
            assert parse_qs(urlsplit(response.url).query)['categoryId'] == [category['categoryId']]
            assert result['page'] == 1
            assert all(v['categoryId'] == category['categoryId'] for v in result['items'])
            expect(p.locator('tbody .video-row')).to_have_count(len(result['items']))
            checks.append({'category_id': category['categoryId'], 'total': result['total']})
        suite.response(admin, '/admin/videos', lambda: p.locator('.btn-reset').click())
        assert data['pageSize'] == 6
        entry['page_size_contract'] = 'N/A selectable sizes: current Admin videos fixes pageSize=6 and renders no page-size control; API page-size support is separate.'
        entry['category_checks'] = checks
        assert categories, 'Real category inventory required'
        suite.api(admin, 'post', '/admin/topics/' + created['categoryId'] + '/archive', data={}, expected=204)
        suite.report['cleanup'].append({'resource': 'delta video category', 'id': created['categoryId'], 'status': 'archived'})
        entry['steps'] = ['Every currently offered category option drives exact categoryId query', 'Each result row belongs to selected category and page resets', 'Reset returns actual default collection', 'Source-reviewed fixed six-row page size; no offered sizes omitted']
    case(suite, admin, 'DELTA-ADMIN-VIDEO-CATEGORY-FIXED-PAGE-SIZE', 'A-VIDEOS.01', 'All offered category filters and current page size contract', collection, 'videos')
    if config.get('delta_admin_category_only'):
        return

    def stats(entry):
        data = load()
        if not data['items']:
            raise PrerequisiteMissing('Actual video required for stats/preview')
        video = data['items'][0]
        row = p.locator('tbody .video-row').first
        row.locator('.row-action-buttons > button').nth(1).click()
        box = p.locator('.stats-overview-box')
        expect(box.locator('h4')).to_have_text(video['title'])
        pills = box.locator('.pill-item strong')
        assert ''.join(c for c in pills.nth(0).inner_text() if c.isdigit()) == str(video['views'])
        expect(pills.nth(1)).to_have_text(str(video['reportCount']))
        expect(pills.nth(2)).to_have_text(video['channelName'])
        suite.evidence(admin, entry, 'stats-exact-row')
        p.locator('.modal-close').click()
        detail = suite.response(admin, '/admin/videos/' + video['videoId'], lambda: row.locator('.row-action-buttons > button').first.click()).json()
        assert detail['video']['videoId'] == video['videoId']
        if detail.get('videoUrl'):
            expect(p.locator('video.preview-player')).to_have_attribute('src', detail['videoUrl'])
            p.wait_for_function('()=>document.querySelector("video.preview-player")?.readyState>=2')
        else:
            expect(p.locator('video.preview-player')).to_have_count(0)
        suite.evidence(admin, entry, 'actual-preview-source-or-unavailable')
        p.locator('.modal-close').click()
        p.reload()
        expect(p.locator('.modal-dialog')).to_have_count(0)
        entry['resource_ids'] = [video['videoId']]
        entry['steps'] = ['Stats modal values match exact API list row', 'Preview requests the same immutable video ID', 'Actual returned stream decodes when available; unavailable stream shows no player', 'Close/reload leaves no stale modal']
    case(suite, admin, 'DELTA-ADMIN-VIDEO-STATS-PREVIEW-SOURCE', 'A-VIDEOS.01', 'Stats and preview belong to selected actual resource', stats, 'videos')

    def race(entry):
        data = load()
        if len(data['items']) < 2:
            raise PrerequisiteMissing('Two actual videos required for metadata target race')
        first, second = data['items'][:2]
        details = {v['videoId']: suite.api(admin, 'get', '/admin/videos/' + v['videoId']).json() for v in (first, second)}
        held = []
        pattern = '**/api/v1/admin/videos/' + first['videoId']
        def delay(route):
            held.append((route, route.fetch()))
        p.route(pattern, delay)
        try:
            p.locator('tbody .video-row').first.locator('.row-action-buttons > button').nth(2).click()
            expect(p.locator('input[name=title]')).to_have_value(first['title'])
            p.wait_for_function('()=>!!document.querySelector(".modal-close")')
            p.locator('.modal-close').click()
            suite.response(admin, '/admin/videos/' + second['videoId'], lambda: p.locator('tbody .video-row').nth(1).locator('.row-action-buttons > button').nth(2).click())
            expect(p.locator('textarea[name=desc]')).to_have_value(details[second['videoId']]['description'] or '')
            assert held, 'First response must actually be delayed'
            route, response = held.pop()
            route.fulfill(response=response)
            p.wait_for_timeout(200)
            expect(p.locator('input[name=title]')).to_have_value(second['title'])
            expect(p.locator('textarea[name=desc]')).to_have_value(details[second['videoId']]['description'] or '')
            p.locator('.modal-close').click()
            for vid, before in details.items():
                after = suite.api(admin, 'get', '/admin/videos/' + vid).json()
                assert after['video']['title'] == before['video']['title'] and after['description'] == before['description']
            entry['resource_ids'] = list(details)
            entry['steps'] = ['Hold genuine first detail HTTP response without replacing payload', 'Close first edit and open second video through UI', 'Deliver first response only after second loaded', 'Second title/description stay bound to second ID; both persisted records unchanged']
        finally:
            for route, response in held:
                route.fulfill(response=response)
            p.unroute(pattern, delay)
    case(suite, admin, 'DELTA-ADMIN-METADATA-LATE-TARGET-RESPONSE', 'A-VIDEOS.02', 'Late previous detail cannot overwrite next edit target', race, 'videos')

    def denied(entry):
        data = load(reviewer)
        if not data['items']:
            raise PrerequisiteMissing('View-only reviewer needs one actual video')
        q = reviewer['page']
        expect(q.locator('tbody .video-row').first.locator('.row-action-buttons > button').nth(2)).to_be_disabled()
        vid = data['items'][0]['videoId']
        before = suite.api(admin, 'get', '/admin/videos/' + vid).json()
        suite.api(reviewer, 'put', '/admin/videos/' + vid + '/metadata', data={'title': 'Denied delta edit', 'reason': 'No video.edit permission'}, expected=403)
        after = suite.api(admin, 'get', '/admin/videos/' + vid).json()
        assert before['video']['title'] == after['video']['title'] and before['description'] == after['description']
        q.reload()
        expect(q.locator('tbody .video-row').first.locator('.row-action-buttons > button').nth(2)).to_be_disabled()
        entry['resource_ids'] = [vid]
        entry['steps'] = ['Actual reviewer has video.view without video.edit', 'UI edit disabled before and after reload', 'Direct actual mutation denied 403', 'Exact target title/description unchanged in admin read-back']
    case(suite, reviewer, 'DELTA-ADMIN-METADATA-PERMISSION-DENIED', 'A-VIDEOS.02', 'View permission never grants metadata edit', denied, 'videos')
