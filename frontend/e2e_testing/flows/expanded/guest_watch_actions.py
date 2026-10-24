"""Uncovered Watch/channel login-return context, actual share and Watch subscription UI."""
from urllib.parse import urlsplit, parse_qs
from playwright.sync_api import expect
from flows.expanded.common import case, snapshot_module
from support.actor_readiness import ensure_actor_pages


def run(suite, config, actors, only_failed=False):
    snapshot_module(suite, __file__)
    guest = suite.actor('guest-watch-actions', 'user', 'guest'); guest['api_url'] = config['api_url']; p = guest['page']
    video = suite.fixtures['video']; vid = video['videoId']; watch = '/watch/' + vid
    channel = suite.fixtures['channel']; public_channel = '/channel/' + channel['handle']
    selectors = [
        ('WATCH-INTERACT', watch, '.reaction-group button:first-child', 'U-WATCH.03'),
        ('WATCH-DOWNLOAD', watch, '.video-actions button[aria-controls=download-popover]', 'U-WATCH.03'),
        ('WATCH-COMMENT', watch, '.comment-composer textarea', 'U-WATCH.03'),
        ('WATCH-SUBSCRIBE', watch, '.channel-actions .primary-button', 'U-WATCH.03'),
        ('CHANNEL-SUBSCRIBE', public_channel, '.btn-subscribe', 'U-CHANNEL.05'),
    ]
    try:
        for key, route, selector, parent in selectors:
            if only_failed and key not in {'WATCH-COMMENT', 'WATCH-SUBSCRIBE', 'CHANNEL-SUBSCRIBE'}: continue
            def context(entry, key=key, route=route, selector=selector):
                suite.go(guest, route, 'app-watch-page' if route == watch else 'app-channel-page')
                if route == watch:
                    expect(p.locator('.reaction-group,.rating-control,.playlist-action-button')).to_have_count(3)
                    expect(p.locator('.comment-composer')).to_be_visible()
                p.locator(selector).click()
                expect(p.locator('.login-prompt')).to_be_visible()
                assert urlsplit(p.url).path == route, 'Protected click must wait for explicit login confirmation'
                p.locator('.prompt-sign-in').click(); p.wait_for_url('**/login**')
                assert parse_qs(urlsplit(p.url).query).get('returnUrl') == [route], key + ' lost exact returnUrl'
                expect(p.locator('#email')).to_be_visible()
                entry['resource_ids'] = [vid, channel['channelId']]
                entry['steps'] = ['Guest sees normal action controls', 'Click actual ' + key + ' control to open anchored login prompt without navigating', 'Confirm login in prompt; exact source returnUrl is preserved without creating subscription/reaction/comment/download']
            case(suite, guest, 'GUEST-' + key + '-LOGIN-CONTEXT', parent, key + ' guest CTA retains its source route', context, 'watch' if route == watch else 'channel')
        if only_failed: return
        def share(entry):
            baseline = suite.api(guest, 'get', '/videos/' + vid).json()['stats']['shares']
            suite.go(guest, watch, 'app-watch-page')
            p.locator('.video-actions button[aria-controls=share-popover]').click()
            expect(p.locator('#share-popover')).to_be_visible()
            expect(p.locator('.share-link-field input')).to_have_value(guest['origin'] + watch)
            p.locator('.share-popover__actions button').click()
            assert p.evaluate('()=>navigator.clipboard.readText()') == guest['origin'] + watch
            expect(p.locator('#share-popover')).to_have_count(0)
            assert suite.api(guest, 'get', '/videos/' + vid).json()['stats']['shares'] == baseline
            for endpoint, body in [('/videos/' + vid + '/reaction', {'type': 'like'}), ('/videos/' + vid + '/rating', {'score': 5})]:
                suite.api(guest, 'put', endpoint, data=body, expected=401)
            suite.api(guest, 'post', '/videos/' + vid + '/comments', data={'content': 'QC denied guest'}, expected=401)
            entry['resource_ids'] = [vid]
            entry['steps'] = ['Guest opens actual share popover with exact public origin/path', 'Copy writes real browser clipboard and closes popover', 'Guest share does not persist protected share counter', 'Actual unauthenticated reaction/rating/comment requests are rejected 401']
        case(suite, guest, 'WATCH-GUEST-SHARE-COPY-AND-MUTATION-GUARDS', 'U-WATCH.03', 'Guest shares exact URL while authenticated mutations remain protected', share, 'watch')
        ensure_actor_pages(suite, actors, ['member'])
        member = actors['member']; q = member['page']; endpoint = '/channels/' + channel['channelId']
        original = suite.api(member, 'get', endpoint + '/subscribe-status').json()
        try:
            def subscription(entry):
                suite.go(member, watch, 'app-watch-page')
                before = suite.api(member, 'get', endpoint + '/subscribe-status').json()['isSubscribed']
                for _ in range(2):
                    method = 'DELETE' if before else 'POST'
                    suite.response(member, endpoint + '/subscribe', lambda: q.locator('.channel-actions .primary-button').click(), method=method, status=(200, 204))
                    persisted = suite.api(member, 'get', endpoint + '/subscribe-status').json()
                    assert persisted['isSubscribed'] is not before
                    before = persisted['isSubscribed']
                    q.reload()
                    expect(q.locator('.channel-actions .primary-button')).to_have_class(__import__('re').compile('is-subscribed') if before else __import__('re').compile(r'^(?!.*is-subscribed).*$'))
                if not before:
                    suite.response(member, endpoint + '/subscribe', lambda: q.locator('.channel-actions .primary-button').click(), method='POST')
                for _ in range(2):
                    baseline = suite.api(member, 'get', endpoint + '/subscribe-status').json()['notificationsEnabled']
                    suite.response(member, endpoint + '/subscribe-notifications', lambda: q.locator('.channel-notification-button').click(), method='PATCH')
                    assert suite.api(member, 'get', endpoint + '/subscribe-status').json()['notificationsEnabled'] is not baseline
                    q.reload()
                    expect(q.locator('.channel-notification-button')).to_be_visible()
                entry['resource_ids'] = [channel['channelId'], vid, member['identity']['userId']]
                entry['steps'] = ['Independent member uses actual Watch subscribe/unsubscribe actions; exact API state persists through reload', 'Watch notification toggle changes persisted flag both directions and survives reload', 'Finally restore original subscription/notification values']
            case(suite, member, 'WATCH-SUBSCRIPTION-NOTIFICATIONS-UI-PERSIST', 'U-WATCH.03', 'Watch subscribe and notifications persist for the correct channel', subscription, 'watch')
        finally:
            suite.go(member, '/account', 'app-account-page', '/account/profile')
            current = suite.api(member, 'get', endpoint + '/subscribe-status').json()
            if current['isSubscribed'] != original['isSubscribed']:
                suite.api(member, 'post' if original['isSubscribed'] else 'delete', endpoint + '/subscribe', data={}, expected=(200, 204))
            if original['isSubscribed']:
                suite.api(member, 'patch', endpoint + '/subscribe-notifications', data={'enabled': original['notificationsEnabled']})
    finally: suite.release_actor(guest)
