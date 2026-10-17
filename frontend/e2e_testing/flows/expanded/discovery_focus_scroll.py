"""Keyboard filter focus, pagination scroll and creator/history viewport orientation."""
import re
from playwright.sync_api import expect
from flows.expanded.common import case, snapshot_module


def run(suite, config, actors, only_creator=False):
    snapshot_module(suite, __file__)
    guest = suite.actor('discovery-focus-scroll', 'user', 'guest'); guest['api_url'] = config['api_url']; p = guest['page']
    try:
        def filter_page(entry):
            result = suite.go(guest, '/search?q=QC', 'app-explore-page', '/videos/search')
            assert result['total'] > 20
            control = p.locator('.filter-grid select').first
            control.focus()
            with p.expect_response(lambda r: '/api/v1/videos/search?' in r.url and 'sort=newest' in r.url):
                control.press('ArrowDown'); control.press('Enter')
            expect(control).to_have_value('newest'); expect(control).to_be_focused()
            p.locator('.pagination .page-button').last.scroll_into_view_if_needed()
            assert p.evaluate('()=>scrollY') > 0
            suite.response(guest, '/videos/search', lambda: p.locator('.pagination .page-button').last.click(), params={'page': 2})
            p.wait_for_function('()=>scrollY<5')
            expect(p.locator('.pagination .is-current')).to_have_text('2')
            entry['steps'] = ['Change real sort through keyboard ArrowDown/Enter; select retains actual focus and chosen value', 'Scroll real first-page result list to pagination', 'Next page request has page=2; deliberate application scroll returns viewport to top and current page matches']
        if not only_creator:
            case(suite, guest, 'DISCOVERY-KEYBOARD-FILTER-PAGE-SCROLL', 'U-DISCOVERY.03', 'Keyboard filters keep focus and paging returns to results top', filter_page, 'discovery')
        def creator(entry):
            suite.go(guest, '/explore', 'app-explore-page')
            link = p.locator('.creator-name').first
            expect(link).to_be_visible()
            p.mouse.wheel(0, 600); p.wait_for_timeout(200)
            link.scroll_into_view_if_needed(); link.focus()
            previous_scroll = p.evaluate('()=>scrollY')
            assert previous_scroll > 0
            href = link.get_attribute('href')
            link.press('Enter')
            expect(p.locator('app-channel-page .channel-name')).to_be_visible()
            assert p.url.endswith(href)
            p.wait_for_function('()=>scrollY<5', timeout=5000)
            suite.evidence(guest, entry, 'creator-route-starts-at-top')
            p.go_back(); expect(p.locator('.featured-creators-section')).to_be_visible()
            p.wait_for_function('(expected)=>Math.abs(scrollY-expected)<100', arg=previous_scroll, timeout=5000)
            assert p.evaluate('()=>document.activeElement?.isConnected')
            entry['steps'] = ['Keyboard activates actual creator link from scrolled Explore section', 'Destination opens exact channel at top instead of inheriting old list offset', 'Browser Back restores Explore scroll position and retains a connected focus target']
        case(suite, guest, 'DISCOVERY-CREATOR-BACK-SCROLL-RESTORATION', 'U-DISCOVERY.03', 'Creator navigation and Back preserve viewport orientation', creator, 'discovery')
    finally: suite.release_actor(guest)
