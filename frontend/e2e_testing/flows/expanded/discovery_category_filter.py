"""Exercise a real Explore category filter, its deep link, and reset behavior."""
import re
from playwright.sync_api import expect
from flows.expanded.common import case, snapshot_module


def run(suite, config, actors):
    snapshot_module(suite, __file__)
    member = actors['member']
    admin = actors['admin']
    page = member['page']
    categories = suite.api(member, 'get', '/categories').json()
    active_categories = [category for category in categories if category.get('status') in (None, 'active')]
    fixture_category = None
    if not active_categories:
        suffix = re.sub(r'[^a-z0-9-]+', '-', suite.run_id.lower()).strip('-')
        fixture_category = suite.api(admin, 'post', '/admin/topics', expected=201, data={
            'name': 'Codex E2E category ' + suffix,
            'slug': 'codex-e2e-category-' + suffix,
            'description': 'Temporary category fixture for Explore filter coverage.',
        }).json()
        categories = suite.api(member, 'get', '/categories').json()
        active_categories = [category for category in categories if category.get('status') in (None, 'active')]
        assert any(category['categoryId'] == fixture_category['categoryId'] for category in active_categories)

    def category_filter_reset(entry):
        selected = None
        selected_data = None
        for category in categories:
            if category.get('status') not in (None, 'active'):
                continue
            data = suite.api(member, 'get', '/videos/search', params={
                'categoryId': category['categoryId'], 'sort': 'views', 'page': 1, 'pageSize': 12,
            }).json()
            if data.get('items'):
                selected, selected_data = category, data
                break
        if selected is None:
            if not active_categories:
                from support.live_suite import PrerequisiteMissing
                raise PrerequisiteMissing('No active category records are available in the QC environment')
            selected = active_categories[0]
            selected_data = suite.api(member, 'get', '/videos/search', params={
                'categoryId': selected['categoryId'], 'sort': 'views', 'page': 1, 'pageSize': 12,
            }).json()
        has_category_videos = bool(selected_data['items'])

        suite.go(member, '/explore', 'app-explore-page')
        expect(page.locator('.category-tabs-bar')).to_be_visible()
        tab = page.locator('.category-tab-pill').filter(has_text=selected['name'])
        expect(tab).to_have_count(1)
        response = suite.response(member, '/videos/search', lambda: tab.click(), params={
            'categoryId': selected['categoryId'], 'sort': 'views', 'pageSize': 12,
        })
        visible_ids = page.locator('.category-top-item').evaluate_all(
            '(cards) => cards.map(card => card.getAttribute("href").split("/").pop())'
        )
        expected_ids = [item['videoId'] for item in selected_data['items']]
        assert response.json()['total'] == selected_data['total']
        assert visible_ids == expected_ids, 'Category tab rendered a different set/order than its real filtered API response'
        expect(page.locator('.category-tab-pill.is-active')).to_contain_text(selected['name'])
        if not has_category_videos:
            expect(page.locator('.empty-category')).to_be_visible()
        suite.evidence(member, entry, 'category-tab-results')

        # The category's View all link leads to a real categoryId search URL.
        expected_deep_link = suite.api(member, 'get', '/videos/search', params={
            'categoryId': selected['categoryId'], 'sort': 'views', 'page': 1, 'pageSize': 20,
        }).json()
        deep_link = suite.response(member, '/videos/search', lambda: page.locator('.ranking-grid-section .view-all-link').click(), params={
            'categoryId': selected['categoryId'], 'sort': 'views',
        }).json()
        expect(page.locator('.search-video-card')).to_have_count(len(deep_link['items']))
        deep_link_ids = page.locator('.search-video-card').evaluate_all(
            '(cards) => cards.map(card => card.getAttribute("href").split("/").pop())'
        )
        assert deep_link_ids == [item['videoId'] for item in expected_deep_link['items']]
        assert deep_link['total'] == expected_deep_link['total']
        if not expected_deep_link['items']:
            expect(page.locator('.empty-state')).to_be_visible()
        assert re.search(r'[?&]categoryId=' + re.escape(selected['categoryId']) + r'(?:&|$)', page.url)

        reset_response = suite.response(
            member, '/feed/explore-hub', lambda: page.locator('.filter-panel .clear-filters').click()
        )
        assert reset_response.status == 200
        expect(page).to_have_url(re.compile(r'/explore(?:\?.*)?$'))
        expect(page.locator('.category-tab-pill.is-active.is-bxh-tong')).to_be_visible()
        expect(page.locator('.category-top-title')).to_be_visible()
        assert 'categoryId' not in page.url and 'sort=' not in page.url
        suite.evidence(member, entry, 'category-filter-reset')

        entry['steps'] = [
            'Choose an active category with actual public video rows when available; otherwise create a temporary active category and confirm the API returns no rows',
            'Select its real Explore pill and compare exact rendered IDs/order/count or empty state with the API response',
            'Open the category View all search route and verify the categoryId filter is retained in results',
            'Clear filters and verify query parameters and the active category reset to the overall hub; archive any temporary category fixture',
        ]
        entry['assertions'] = [
            'Category selection sends the correct categoryId and sort/pageSize request',
            'Rendered category videos and count match actual API data',
            'An empty category shows the actual empty state with no stale category cards',
            'Category deep link returns the same filtered rows',
            'Clear filters removes categoryId/sort and returns to overall Explore',
        ]
        entry['resource_ids'] = [selected['categoryId']] + [item['videoId'] for item in selected_data['items']]
        if not has_category_videos:
            entry['precondition_note'] = 'QC data contains no public videos assigned to any active category; tested the actual category empty state, retained category deep link, and reset.'

    try:
        case(
            suite,
            member,
            'DISCOVERY-CATEGORY-FILTER-RESET',
            'U-DISCOVERY.02',
            'Explore category filter, deep link and reset match real API data',
            category_filter_reset,
            'discovery',
        )
    finally:
        if fixture_category:
            suite.api(
                admin,
                'post',
                '/admin/topics/' + fixture_category['categoryId'] + '/archive',
                expected=(200, 204),
                data={},
            )
