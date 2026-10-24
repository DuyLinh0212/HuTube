"""Missing comment reaction/sort and second-page UI behavior on real rows."""
from playwright.sync_api import expect
from flows.expanded.common import case, snapshot_module
from support.actor_readiness import ensure_actor_pages


def run(suite, config, actors, only_pagination=False):
    snapshot_module(suite, __file__)
    ensure_actor_pages(suite, actors, ['owner', 'member'])
    owner, member = actors['owner'], actors['member']; p = member['page']
    vid = suite.fixtures['video']['videoId']; endpoint = '/videos/' + vid + '/comments'; created = []
    try:
        for index in range(21):
            created.append(suite.api(member, 'post', endpoint, data={'content': 'QC comments page ' + suite.run_id + ' ' + str(index)}, expected=201).json())
        def actual_comments(response):
            expect(p.locator('.comment-list > .comment-row > .comment-body > p')).to_have_text([item['content'] for item in response['items']])
        if not only_pagination:
            def reaction(entry):
                response = suite.go(member, '/watch/' + vid, 'app-watch-page', endpoint)
                actual_comments(response)
                target = response['items'][0]; path = '/comments/' + target['commentId'] + '/reaction'
                row = p.locator('.comment-list > .comment-row').filter(has_text=target['content'])
                buttons = row.locator(':scope > .comment-body > .comment-actions > button')
                for index, expected in [(0, 'like'), (1, 'dislike')]:
                    result = suite.response(member, path, lambda: buttons.nth(index).click(), method='PUT').json()
                    assert result['myReaction'] == expected
                    expect(buttons.nth(index)).to_have_attribute('aria-pressed', 'true')
                    persisted = suite.api(member, 'get', endpoint, params={'pageSize': 50}).json()
                    assert next(item for item in persisted['items'] if item['commentId'] == target['commentId'])['myReaction'] == expected
                cleared = suite.response(member, path, lambda: buttons.nth(1).click(), method='DELETE').json()
                assert cleared['myReaction'] is None
                for sort in ['top', 'newest']:
                    response = suite.response(member, endpoint, lambda: p.locator('.comments-sort select').select_option(sort), params={'sort': sort, 'page': 1}).json()
                    actual_comments(response)
                    suite.evidence(member, entry, sort + '-actual-comments')
                p.reload()
                expect(p.locator('.comments-sort select')).to_have_value('newest')
                expect(p.locator('.comment-list > .comment-row').filter(has_text=target['content']).locator(':scope > .comment-body > .comment-actions > button').nth(1)).to_have_attribute('aria-pressed', 'false')
                entry['resource_ids'] = [target['commentId'], vid]
                entry['steps'] = ['Actual comment UI like/dislike/clear sends real PUT/DELETE and matches persisted myReaction', 'Both offered sorts render exactly the real ordered API comments', 'Reload retains cleared reaction; no video reaction or other actor data is changed']
            case(suite, member, 'WATCH-COMMENT-REACTIONS-SORT-PERSIST', 'U-WATCH.04', 'Comment reactions and both sorts match actual persisted rows', reaction, 'comments')
        def pagination(entry):
            first = suite.go(member, '/watch/' + vid, 'app-watch-page', endpoint)
            assert first['total'] > first['pageSize'] == 20
            actual_comments(first)
            button = p.locator('.comments-load-more')
            expect(button).to_be_visible()
            pattern = '**/api/v1/videos/' + vid + '/comments?*'
            def offline(request):
                if 'page=2&' in request.request.url or request.request.url.endswith('page=2'): request.abort('internetdisconnected')
                else: request.continue_()
            p.route(pattern, offline)
            try:
                button.click()
                expect(p.locator('.comments-section [role=alert]')).to_be_visible()
                actual_comments(first)
                suite.evidence(member, entry, 'second-page-error-keeps-first-page')
            finally: p.unroute(pattern, offline)
            second = suite.response(member, endpoint, lambda: p.locator('.comments-retry').click(), params={'page': 2}).json()
            ids = [item['commentId'] for item in first['items'] + second['items']]
            assert len(ids) == len(set(ids))
            expect(p.locator('.comment-list > .comment-row > .comment-body > p')).to_have_text([item['content'] for item in first['items'] + second['items']])
            suite.evidence(member, entry, 'second-comment-page-actual-rows')
            new_text = 'QC create while paged ' + suite.run_id
            p.locator('textarea[name=comment]').fill(new_text)
            with p.expect_response(lambda response: response.request.method == 'GET' and '/api/v1' + endpoint + '?' in response.url and 'page=1&' in response.url) as refreshed:
                new_item = suite.response(member, endpoint, lambda: p.locator('.comment-composer button[type=submit]').click(), method='POST', status=201).json()
            created.append(new_item)
            actual_comments(refreshed.value.json())
            response = suite.response(member, endpoint, lambda: p.locator('.comments-sort select').select_option('top'), params={'sort': 'top', 'page': 1}).json()
            actual_comments(response)
            entry['resource_ids'] = ids
            entry['steps'] = ['Prepare 21 new real comments so genuine first page has a successor', 'Abort page-2 transport: error retains exact first page, retry obtains genuine next page', 'Appended exact real rows are disjoint', 'Create while paged refreshes page 1 to avoid shifted-page omissions', 'Changing sort resets first page without stale appended comments']
        case(suite, member, 'WATCH-COMMENTS-SECOND-PAGE-EXACT', 'U-WATCH.04', 'Watch can display comments beyond its first twenty rows', pagination, 'comments')
    finally:
        suite.go(member, '/account', 'app-account-page', '/account/profile')
        for item in created: suite.api(member, 'delete', '/comments/' + item['commentId'], expected=(204, 404))
