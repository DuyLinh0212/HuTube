"""Exercise genuine browser media/API network failures and recovery without fabricating a playback response."""
import re

from playwright.sync_api import expect

from flows.expanded.common import case, snapshot_module
from support.actor_readiness import ensure_actor_pages


def run(suite, config, actors):
    snapshot_module(suite, __file__)
    ensure_actor_pages(suite, actors, ['member'])
    member = actors['member']; page = member['page']; video_id = suite.fixtures['video']['videoId']
    watch = '/watch/' + video_id
    playback = suite.api(member, 'get', '/videos/' + video_id + '/playback').json()
    renditions = sorted(playback['renditions'], key=lambda item: item['height'], reverse=True)
    assert renditions, 'Fixture needs a real rendition for missing-media certification'
    highest = renditions[0]
    source_url = suite.api(member, 'get', '/videos/' + video_id).json().get('videoUrl')
    fallback = next((item for item in renditions[1:] if item['url'] != highest['url']), None)
    fallback_url = fallback['url'] if fallback else (source_url if source_url and source_url != highest['url'] else None)

    def missing_rendition(entry):
        failed = []
        def intercept(route):
            failed.append(route.request.url)
            route.abort('failed')
        page.route(re.compile('^' + re.escape(highest['url']) + '$'), intercept)
        try:
            suite.go(member, watch, 'app-watch-page')
            expect(page.locator('video')).to_be_visible()
            if fallback_url:
                page.wait_for_function("""expected => {
                    const v = document.querySelector('video');
                    return !!v && !v.currentSrc.includes(expected) && v.readyState >= 1;
                }""", highest['url'], timeout=30000)
            else:
                page.wait_for_function('() => !!document.querySelector("app-result-notice[tone=info]")', timeout=30000)
            expect(page.locator('app-result-notice[tone=info]')).to_be_visible(timeout=15000)
            expect(page.locator('app-result-notice[tone=info]')).to_contain_text('chất lượng thấp hơn' if fallback else ('tệp nguồn' if fallback_url else 'Không thể phát'))
            if fallback_url:
                assert fallback_url in page.locator('video').evaluate('(v) => v.currentSrc')
            else:
                assert highest['url'] not in page.locator('app-result-notice[tone=info]').inner_text()
            assert failed and highest['url'] in failed
            entry['resource_ids'] = [video_id]
            entry['steps'] = ['Abort only the actual highest rendition browser request', 'Watch selects a lower real rendition/source when one is available, otherwise shows the bounded rendition error', 'No response is stubbed and the failed signed URL is not rendered into the page']
        finally:
            page.unroute(re.compile('^' + re.escape(highest['url']) + '$'), intercept)
    if not config.get('watch_network_only'):
        case(suite, member, 'WATCH-MISSING-RENDITION-LOWER-QUALITY-RECOVERY', 'U-WATCH.05', 'Missing highest rendition falls back to a real lower-quality stream', missing_rendition, 'watch')

    def retry_playback_request(entry):
        failed = []
        pattern = re.compile(r'.*/api/v1/videos/' + re.escape(video_id) + r'/playback(?:\\?.*)?$')
        def intercept(route):
            failed.append(route.request.url)
            route.abort('failed')
        page.route(pattern, intercept)
        try:
            suite.go(member, watch, 'app-watch-page')
            expect(page.locator('app-watch-page')).to_be_visible()
            expect(page.locator('app-result-notice[tone=info]')).to_be_visible(timeout=15000)
            expect(page.locator('video[src]')).to_have_count(0)
            assert failed
        finally:
            page.unroute(pattern, intercept)
        page.reload()
        page.wait_for_function('() => document.querySelector("video")?.readyState >= 1', timeout=30000)
        expect(page.locator('video[src]').first).to_be_visible()
        entry['resource_ids'] = [video_id]
        entry['steps'] = ['Abort only genuine playback API transport and require visible bounded error without a media source', 'Remove transport failure and reload the same Watch route', 'Actual API/rendition succeeds after retry; no synthetic playback response is used']
    case(suite, member, 'WATCH-PLAYBACK-NETWORK-RETRY-REAL-RECOVERY', 'U-WATCH.05', 'Playback API network failure recovers on same-route retry', retry_playback_request, 'watch')
