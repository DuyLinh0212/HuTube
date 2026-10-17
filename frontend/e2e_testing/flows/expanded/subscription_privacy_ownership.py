"""Private own subscriptions cannot be queried or mutated by a foreign identity parameter."""
from playwright.sync_api import expect
from flows.expanded.common import case, snapshot_module
from support.actor_readiness import ensure_actor_pages


def run(suite, config, actors):
    snapshot_module(suite, __file__)
    ensure_actor_pages(suite, actors, ['member', 'target'])
    member, foreign = actors['member'], actors['target']; channel = suite.fixtures['channel']; cid = channel['channelId']
    endpoint = '/channels/' + cid
    original = suite.api(member, 'get', endpoint + '/subscribe-status').json()
    original_privacy = suite.api(member, 'get', '/account/settings').json()
    original_foreign = suite.api(foreign, 'get', endpoint + '/subscribe-status').json()
    try:
        if not original['isSubscribed']: suite.api(member, 'post', endpoint + '/subscribe', data={})
        if original_foreign['isSubscribed']: suite.api(foreign, 'delete', endpoint + '/subscribe', expected=(200, 204))
        suite.api(member, 'put', '/account/settings', data={**original_privacy, 'keepSubscriptionsPrivate': True})
        def isolation(entry):
            own = suite.api(member, 'get', '/subscriptions').json()
            assert any(row['channelId'] == cid for row in own)
            own_sub = suite.api(member, 'get', endpoint + '/subscribe-status').json()
            overridden = suite.api(foreign, 'get', '/subscriptions', params={'userId': member['identity']['userId']}).json()
            assert all(row['channelId'] != cid for row in overridden)
            suite.api(foreign, 'patch', endpoint + '/subscribe-notifications?userId=' + member['identity']['userId'], data={'enabled': not own_sub['notificationsEnabled']}, expected=(400, 403, 404))
            suite.api(foreign, 'delete', endpoint + '/subscribe?userId=' + member['identity']['userId'], expected=(200, 204))
            assert suite.api(member, 'get', endpoint + '/subscribe-status').json() == own_sub
            assert suite.api(member, 'get', '/account/settings').json()['keepSubscriptionsPrivate'] is True
            p = foreign['page']
            suite.go(foreign, '/channel/' + channel['handle'], 'app-channel-page')
            expect(p.locator('app-channel-page a[href="/subscriptions"]')).to_have_count(0)
            expect(p.locator('.channel-tabs-bar button')).to_have_count(3)
            entry['verified_na'] = ['Public channel offers Home/Videos/Playlists only. There is no public user subscription-list surface in routes/controller/template; privacy=false does not create such a feature.']
            entry['resource_ids'] = [cid, member['identity']['userId'], foreign['identity']['userId']]
            entry['steps'] = ['Prepare a known private own subscription and a separate unsubscribed actor', 'Foreign userId query cannot read this subscription; actual result remains bound to authenticated subject', 'Foreign notification update rejects; foreign DELETE cannot revoke the real member subscription', 'Exact real member flags and private preference remain unchanged; public UI exposes no subscription list']
        case(suite, foreign, 'SUBSCRIPTION-PRIVATE-OWNERSHIP-NO-OVERRIDE', 'U-SUBSCRIPTION.01', 'Private subscription APIs use authenticated ownership regardless of userId input', isolation, 'subscriptions')
    finally:
        ensure_actor_pages(suite, actors, ['member', 'target'])
        member, foreign = actors['member'], actors['target']
        suite.api(member, 'put', '/account/settings', data=original_privacy)
        for actor, before in [(member, original), (foreign, original_foreign)]:
            current = suite.api(actor, 'get', endpoint + '/subscribe-status').json()
            if current['isSubscribed'] != before['isSubscribed']:
                suite.api(actor, 'post' if before['isSubscribed'] else 'delete', endpoint + '/subscribe', data={}, expected=(200, 204))
            if before['isSubscribed']: suite.api(actor, 'patch', endpoint + '/subscribe-notifications', data={'enabled': before['notificationsEnabled']})
