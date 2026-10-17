"""Exact channel sort, page-size and page results on a genuine multi-page dataset."""
import time
from urllib.parse import urlsplit, parse_qs
from playwright.sync_api import expect
from flows.expanded.common import case, snapshot_module
from tests.full_functional import pickup_link
from support.actor_readiness import ensure_actor_pages


def run(suite, config, actors):
    snapshot_module(suite, __file__)
    ensure_actor_pages(suite, actors, ['admin'])
    admin = actors['admin']; p = admin['page']; fixtures = []
    def prepare(status, number):
        for index in range(number):
            stamp = str(time.time_ns())
            actor = suite.actor('channel-page-fixture-' + stamp, 'user', 'guest')
            actor['api_url'] = config['api_url']
            actor['headers'].update({'X-HuTube-Client': 'web', 'Origin': actor['origin']})
            credentials = {'email': 'qc.page.' + stamp + '@example.test', 'username': 'qc_pg_' + stamp, 'password': 'QCFixturePassword2026!'}
            sent = time.time()
            suite.api(actor, 'post', '/auth/register', data={**credentials, 'displayName': 'QC owner ' + stamp}, expected=201)
            token = parse_qs(urlsplit(pickup_link(config, credentials['email'], 'verify-email', sent)).query)['token'][0]
            suite.api(actor, 'post', '/auth/verify-email', data={'token': token})
            login = suite.api(actor, 'post', '/auth/login', data=credentials).json()
            actor['headers']['Authorization'] = 'Bearer ' + login['accessToken']
            actor['identity'] = login['user']
            channel = suite.api(actor, 'post', '/channels', data={'name': 'QC pagination ' + stamp, 'handle': 'qc-page-' + stamp}, expected=201).json()
            fixtures.append((actor, channel))
            suite.report['setup'].append({'resource': 'owned pagination channel', 'id': channel['channelId'], 'status': status, 'handle': channel['handle']})
            if status != 'active':
                suite.api(admin, 'post', '/admin/channels/' + channel['channelId'] + ('/suspend' if status == 'suspended' else '/ban'), data={'reason': 'Owned pagination fixture'}, expected=204)
            suite.release_actor(actor)
    try:
        for status, needed in [('active', 9), ('suspended', 2), ('banned', 2)]:
            data = suite.api(admin, 'get', '/admin/channels', params={'status': status, 'pageSize': 8}).json()
            prepare(status, max(0, needed - data['total']))
        ensure_actor_pages(suite, actors, ['admin'])
        admin = actors['admin']; p = admin['page']
        def collection(entry):
            suite.go(admin, '/channels', 'app-admin-channels-page', '/admin/channels')
            def rows(response):
                items = response['items']
                expect(p.locator('.channel-row')).to_have_count(len(items))
                for index, channel in enumerate(items):
                    expect(p.locator('.channel-row').nth(index)).to_contain_text(channel['handle'])
                return [channel['channelId'] for channel in items]
            checks = []
            columns = ['name', 'owner', 'videoCount', 'subscriberCount', 'views', 'status', 'createdAt']
            for index, status in enumerate(['', 'active', 'suspended', 'banned']):
                if index == 0:
                    suite.response(admin, '/admin/channels', lambda: p.locator('.channel-tabs button').nth(1).click(), params={'status': 'active'})
                data = suite.response(admin, '/admin/channels', lambda: p.locator('.channel-tabs button').nth(index).click(), params={'status': status}).json()
                rows(data)
                if status: assert all(v['status'] == status for v in data['items'])
                for size in ['10', '20', '50', '8']:
                    response = suite.response(admin, '/admin/channels', lambda: p.locator('.page-size-select-wrap select').select_option(size), params={'pageSize': size, 'page': 1}).json()
                    rows(response)
                    assert len(response['items']) == min(int(size), response['total'])
                    checks.append({'status': status or 'all', 'size': int(size), 'total': response['total']})
                for column_index, column in enumerate(columns):
                    for direction in ['desc', 'asc']:
                        response = suite.response(admin, '/admin/channels', lambda: p.locator('th.col-sortable').nth(column_index).click()).json()
                        expected = suite.api(admin, 'get', '/admin/channels', params={'status': status, 'page': 1, 'pageSize': 8, 'sortBy': column, 'sortDescending': direction == 'desc'}).json()
                        assert rows(response) == [v['channelId'] for v in expected['items']]
                        assert response['total'] == expected['total']
                suite.evidence(admin, entry, 'sort-size-' + (status or 'all'))
                if status in ('', 'active'):
                    first = rows(response)
                    second = suite.response(admin, '/admin/channels', lambda: p.locator('.page-arrow').nth(1).click(), params={'page': 2}).json()
                    ids = rows(second)
                    assert second['total'] == response['total'] and not set(first).intersection(ids)
                    back = suite.response(admin, '/admin/channels', lambda: p.locator('.page-arrow').nth(0).click(), params={'page': 1}).json()
                    assert rows(back) == first
                    suite.evidence(admin, entry, 'multi-page-' + (status or 'all'))
            entry['resource_ids'] = [channel['channelId'] for _, channel in fixtures]
            entry['page_size_checks'] = checks
            entry['steps'] = ['Prepare owned real channels until active data exceeds page size 8, and each status tab has rows', 'All four tabs: exact real rendered order for each visible sort column ascending/descending', 'All offered sizes 8/10/20/50: first page resets and rows/total agree with same backend query', 'Actual next and previous on populated all/active tabs: no duplicate IDs and exact first-page restoration', 'Cleanup only owned fixture channels through real APIs']
        case(suite, admin, 'ADMIN-CHANNELS-SORT-PAGE-SIZE-EXACT', 'A-CHANNELS.01', 'Channel tabs sort and paginate exact real rows', collection, 'channels')
    finally:
        for actor, channel in reversed(fixtures):
            try:
                suite.api(admin, 'delete', '/admin/channels/' + channel['channelId'], data={'reason': 'QC owned pagination fixture cleanup', 'notifyOwner': False}, expected=(200, 204))
                suite.report['cleanup'].append({'resource': 'owned pagination channel', 'id': channel['channelId'], 'status': 'deleted through Admin API'})
            finally:
                suite.release_actor(actor)
