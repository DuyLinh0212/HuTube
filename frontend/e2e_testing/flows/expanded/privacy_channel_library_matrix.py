"""Actual privacy/channel states must hide persisted library data and media from foreign users."""
from playwright.sync_api import expect
from flows.expanded.common import case, snapshot_module
from support.actor_readiness import ensure_actor_pages
from support.owned_public_media import prepare


def run(suite, config, actors):
    snapshot_module(suite, __file__)
    ensure_actor_pages(suite, actors, ['admin', 'member'])
    admin = actors['admin']; owner, channel, video = prepare(suite, config, admin)
    vid, cid = video['videoId'], channel['channelId']; deleted = False
    member = actors['member']; p = member['page']
    source_urls = []
    def ready():
        nonlocal member, p, admin
        ensure_actor_pages(suite, actors, ['admin', 'member'])
        admin, member = actors['admin'], actors['member']; p = member['page']
    def library(path):
        rows = []; page = 1
        while True:
            data = suite.api(member, 'get', path, params={'page': page, 'pageSize': 50}).json(); rows.extend(data['items'])
            if page * data['pageSize'] >= data['total']: return rows
            page += 1
    def blocked(entry, label):
        for suffix in ['', '/playback']:
            response = suite.api(member, 'get', '/videos/' + vid + suffix, expected=(403, 404, 409))
            payload = response.json()
            assert not {'videoUrl', 'thumbnailUrl', 'renditions'}.intersection(payload)
            assert payload.get('title') != video['title']
            assert video['title'] not in response.text()
            assert all(url not in response.text() for url in source_urls)
        for endpoint in ['/library/history', '/library/liked']:
            assert all(item['videoId'] != vid for item in library(endpoint))
        suite.go(member, '/watch/' + vid, 'app-watch-page')
        expect(p.locator('.watch-state')).to_be_visible()
        expect(p.locator('video[src]')).to_have_count(0)
        suite.evidence(member, entry, label + '-watch-denied')
        for route, endpoint in [('/history', '/library/history'), ('/liked', '/library/liked')]:
            suite.go(member, route, 'app-library-page', endpoint)
            expect(p.locator('a[href="/watch/' + vid + '"]')).to_have_count(0)
            expect(p.locator('app-library-page')).not_to_contain_text(video['title'])
            suite.evidence(member, entry, label + '-' + route[1:])
        primary = suite.api(member, 'get', '/channels/handle/' + suite.fixtures['channel']['handle']).json()
        assert primary['channelId'] == suite.fixtures['channel']['channelId'] and primary['status'] == 'active'
        entry['resource_ids'] = [vid, cid, member['identity']['userId'], primary['channelId']]
        entry['steps'] = ['Real source previously appeared in this foreign viewer history and liked library', 'Actual ' + label + ' mutation blocks detail/playback without metadata/source URL fields', 'Every actual library API page excludes ID; history/liked UI omit title and link', 'Watch denies with no media source and unrelated primary channel stays active']
    try:
        ready()
        playback = suite.api(member, 'get', '/videos/' + vid + '/playback').json()
        source_urls.extend(item['url'] for item in playback['renditions'] if item.get('url'))
        assert source_urls, 'Actual source URLs must be established before testing restricted responses'
        suite.api(member, 'put', '/videos/' + vid + '/watch-progress', data={'watchedSeconds': 2})
        suite.api(member, 'put', '/videos/' + vid + '/reaction', data={'type': 'like'})
        assert any(item['videoId'] == vid for item in library('/library/history'))
        assert any(item['videoId'] == vid for item in library('/library/liked'))
        def private(entry):
            ready(); suite.go(owner, '/account', 'app-account-page', '/account/profile')
            suite.api(owner, 'patch', '/videos/' + vid, data={'visibility': 'private'})
            try: blocked(entry, 'private')
            finally:
                suite.go(owner, '/account', 'app-account-page', '/account/profile')
                suite.api(owner, 'patch', '/videos/' + vid, data={'visibility': 'public'})
        case(suite, member, 'LIBRARY-PRIVATE-SOURCE-NO-METADATA-LEAK', 'U-LIBRARY.02', 'Saved private source cannot leak through foreign library or Watch', private, 'library')
        def hidden(entry):
            ready(); suite.api(admin, 'post', '/admin/videos/' + vid + '/hide', data={'reason': 'QC owned privacy fixture only', 'notifyOwner': False}, expected=204)
            try: blocked(entry, 'hidden')
            finally:
                ensure_actor_pages(suite, actors, ['admin'])
                suite.api(actors['admin'], 'post', '/admin/videos/' + vid + '/unhide', data={'reason': 'QC restore owned privacy fixture', 'notifyOwner': False}, expected=204)
        case(suite, member, 'LIBRARY-HIDDEN-SOURCE-NO-METADATA-LEAK', 'U-LIBRARY.02', 'Saved hidden source cannot leak through foreign library or Watch', hidden, 'library')
        for status, endpoint in [('suspended', 'suspend'), ('banned', 'ban')]:
            def restricted(entry, status=status, endpoint=endpoint):
                ready(); suite.api(admin, 'post', '/admin/channels/' + cid + '/' + endpoint, data={'reason': 'QC owned channel state matrix', 'notifyOwner': False}, expected=204)
                try: blocked(entry, status)
                finally:
                    ensure_actor_pages(suite, actors, ['admin'])
                    suite.api(actors['admin'], 'post', '/admin/channels/' + cid + '/unban', data={'reason': 'QC restore owned channel fixture', 'notifyOwner': False}, expected=204)
            case(suite, member, 'CHANNEL-' + status.upper() + '-PLAYBACK-LIBRARY-ISOLATION', 'U-CHANNEL.06', status + ' channel denies public playback and saved metadata', restricted, 'channel')
        def delete(entry):
            nonlocal deleted
            ready(); a = admin['page']
            suite.go(admin, '/channels', 'app-admin-channels-page', '/admin/channels')
            a.locator('.search-box input').fill(channel['handle'])
            suite.response(admin, '/admin/channels', lambda: a.locator('.btn-filter').click(), params={'search': channel['handle']})
            row = a.locator('.channel-row').filter(has_text=channel['handle'])
            def open_delete():
                row.locator('.btn-dots').click(); a.locator('.dropdown-menu .menu-item').last.click()
                expect(a.locator('.modal-dialog .btn-modal-confirm')).to_be_disabled()
                a.locator('.modal-textarea').fill('QC owned fixture channel deletion')
            open_delete(); a.locator('.btn-modal-cancel').click()
            assert suite.api(member, 'get', '/channels/handle/' + channel['handle']).json()['channelId'] == cid
            open_delete(); a.locator('.modal-checkbox-label input').uncheck()
            suite.response(admin, '/admin/channels/' + cid, lambda: a.locator('.btn-modal-confirm').click(), method='DELETE', status=204)
            deleted = True
            blocked(entry, 'deleted-channel')
        case(suite, admin, 'ADMIN-CHANNEL-DELETE-CANCEL-REASON-PLAYBACK', 'A-CHANNELS.02', 'Only confirmed Admin channel deletion blocks the exact source', delete, 'channels')
    finally:
        ensure_actor_pages(suite, actors, ['admin'])
        if deleted:
            suite.report['cleanup'].append({'resource': 'owned privacy fixture channel', 'id': cid, 'status': 'deleted by tested Admin action; audit evidence retained'})
        else:
            suite.api(actors['admin'], 'post', '/admin/channels/' + cid + '/unban', data={'reason': 'QC cleanup restore owned fixture', 'notifyOwner': False}, expected=204)
            suite.go(owner, '/account', 'app-account-page', '/account/profile')
            suite.api(owner, 'delete', '/videos/' + vid, expected=(200, 204))
            suite.api(owner, 'delete', '/channels/' + cid, expected=(200, 204))
        suite.release_actor(owner)
