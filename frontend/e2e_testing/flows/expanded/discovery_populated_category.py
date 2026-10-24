"""Previously missing nonempty category and diacritic-equivalent search assertions."""
from playwright.sync_api import expect
from flows.expanded.common import case, snapshot_module


def run(suite, config, actors, only_failed=False):
    snapshot_module(suite, __file__)
    owner, admin, member = actors['owner'], actors['admin'], actors['member']
    p = member['page']
    vid = suite.fixtures['video']['videoId']
    original = suite.api(owner, 'get', '/videos/' + vid).json()
    category = suite.api(admin, 'post', '/admin/topics', data={'name': 'QC populated ' + suite.run_id, 'slug': 'qc-populated-' + suite.run_id[9:15]}, expected=201).json()
    cid = category['categoryId']
    title = 'Bản nhạc mùa thu qc' + suite.run_id[9:15]
    try:
        suite.api(owner, 'patch', '/videos/' + vid, data={'categoryId': cid, 'title': title})
        def populated(entry):
            expected = suite.api(member, 'get', '/videos/search', params={'categoryId': cid, 'sort': 'views', 'pageSize': 12}).json()
            assert [v['videoId'] for v in expected['items']] == [vid]
            suite.go(member, '/explore', 'app-explore-page')
            tab = p.locator('.category-tab-pill').filter(has_text=category['name'])
            suite.response(member, '/videos/search', lambda: tab.click(), params={'categoryId': cid, 'sort': 'views'})
            expect(p.locator('.category-top-item')).to_have_count(1)
            expect(p.locator('.category-top-item')).to_have_attribute('href', '/watch/' + vid)
            expect(p.locator('.category-top-item')).to_contain_text(title)
            expect(p.locator('.empty-category')).to_have_count(0)
            entry['resource_ids'] = [cid, vid]
            entry['steps'] = ['Assign a real approved public video to an owned temporary active category through owner API', 'Actual Explore category selection sends exact categoryId', 'Nonempty UI renders exact API ID and Unicode title; no empty-state fallback']
        if not only_failed:
            case(suite, member, 'DISCOVERY-CATEGORY-NONEMPTY-EXACT-VIDEO', 'U-DISCOVERY.02', 'Populated category renders its actual eligible source', populated, 'discovery')
        def diacritics(entry):
            ids = []
            for query in [title, 'Ban nhac mua thu qc' + suite.run_id[9:15]]:
                result = suite.go(member, '/search?q=' + __import__('urllib.parse', fromlist=['quote']).quote(query), 'app-explore-page', '/videos/search')
                rendered = p.locator('.search-video-card').evaluate_all('(rows)=>rows.map(a=>a.pathname.split("/").pop())')
                actual = [v['videoId'] for v in result['items']]
                assert rendered == actual and vid in actual
                ids.append(actual)
                suite.evidence(member, entry, 'accented' if len(ids) == 1 else 'unaccented')
            assert ids[0] == ids[1]
            entry['resource_ids'] = [vid]
            entry['steps'] = ['Search real unique Vietnamese title with diacritics', 'Search its unaccented equivalent through actual UI route/API', 'Both exact rendered result-ID sequences match and include the same source']
        case(suite, member, 'DISCOVERY-DIACRITIC-EQUIVALENT-RESULTS', 'U-DISCOVERY.02', 'Accented and unaccented search return the same exact source', diacritics, 'discovery')
    finally:
        suite.api(owner, 'patch', '/videos/' + vid, data={'title': original['title'], 'categoryId': original.get('categoryId'), 'clearCategory': original.get('categoryId') is None})
        suite.api(admin, 'post', '/admin/topics/' + cid + '/archive', data={}, expected=(200, 204))
