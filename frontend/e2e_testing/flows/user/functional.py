"""User Web functional cases; mutations only use managed E2E fixtures."""
from playwright.sync_api import expect


def run(suite, owner, member):
    page = owner['page']
    api = suite.config['api_url']
    channel = {}

    def create_channel():
        existing = suite.api(owner, 'get', '/channels/me')
        if existing.status == 200:
            channel.update(existing.json())
            suite.go(owner, '/channel/' + channel['handle'], 'app-channel-page')
            expect(page.locator('h1')).to_contain_text(channel['name'])
            return 'reused'
        assert existing.status == 404
        suite.go(owner, '/channel/create', 'app-channel-create-page')
        page.locator('#channelName').fill('HuTube E2E — Học tập và sáng tạo')
        page.locator('#channelHandle').fill('hutube_web_learning')
        page.locator('#channelDescription').fill('Kênh fixture cho kiểm thử Web trong database E2E riêng.')
        expect(page.locator('.feedback-text.is-valid')).to_be_visible()
        with page.expect_response(lambda r: r.request.method == 'POST' and r.url == api + '/channels') as response:
            page.locator('button[type=submit]').click()
        assert response.value.status == 201
        channel.update(response.value.json())
        suite.state['channel'] = {'channel_id': channel['channelId'], 'handle': channel['handle']}
        suite.save()
        page.wait_for_url('**/channel/' + channel['handle'])
        expect(page.locator('app-channel-page h1')).to_contain_text(channel['name'])
        assert suite.api(owner, 'get', '/channels/me').json()['channelId'] == channel['channelId']
    suite.case(owner, 'U-CHANNEL-CREATE-01', 'Tạo hoặc mở lại kênh fixture', create_channel, expected='Kênh đúng owner; create 201 và GET cùng ID', steps='Mở tạo kênh, nhập tên/handle/mô tả, submit, đối chiếu API')

    if channel:
        def public_channel():
            suite.go(member, '/channel/' + channel['handle'], 'app-channel-page')
            expect(member['page'].locator('h1')).to_contain_text(channel['name'])
            assert suite.api(member, 'get', '/channels/handle/' + channel['handle']).status == 200
        suite.case(member, 'U-CHANNEL-PUBLIC-01', 'Member đọc kênh public của owner', public_channel, expected='UI và API cùng kênh')

        def subscribe_cycle():
            target = member['page']
            suite.go(member, '/channel/' + channel['handle'], 'app-channel-page')
            status = suite.api(member, 'get', '/channels/' + channel['channelId'] + '/subscribe-status')
            assert status.status in (200, 404)
            original = status.status == 200 and status.json()['status'] == 'active'
            method = 'DELETE' if original else 'POST'
            with target.expect_response(lambda r: r.request.method == method and r.url.endswith('/subscribe')) as response:
                target.locator('.btn-subscribe').click()
            assert response.value.status in (200, 204)
            changed = suite.api(member, 'get', '/channels/' + channel['channelId'] + '/subscribe-status')
            assert (changed.status == 200 and changed.json()['status'] == 'active') != original
            with target.expect_response(lambda r: r.request.method != method and r.url.endswith('/subscribe')) as response:
                target.locator('.btn-subscribe').click()
            assert response.value.status in (200, 204)
            restored = suite.api(member, 'get', '/channels/' + channel['channelId'] + '/subscribe-status')
            assert (restored.status == 200 and restored.json()['status'] == 'active') == original
        suite.case(member, 'U-CHANNEL-SUBSCRIBE-01', 'Subscribe/unsubscribe qua UI và đối chiếu API', subscribe_cycle,
                   expected='Trạng thái đổi đúng rồi phục hồi; không subscribe lặp')

    playlists = {}
    def playlist_create():
        suite.go(owner, '/playlists', 'app-playlists-page')
        expect(page.locator('.create-card button.full-button')).to_be_disabled()
        existing = suite.api(owner, 'get', '/playlists')
        assert existing.status == 200
        matches = [item for item in existing.json() if item['name'] == 'HuTube E2E — Bài học trách nhiệm']
        if matches:
            playlists.update(matches[0])
            suite.go(owner, '/playlists/' + playlists['playlistId'], 'app-playlists-page')
            expect(page.locator('.hero-copy h1')).to_contain_text(playlists['name'])
            return 'reused'
        page.locator('#playlist-name').fill('HuTube E2E — Bài học trách nhiệm')
        page.locator('#playlist-description').fill('Bộ sưu tập fixture E2E')
        page.locator('#playlist-visibility').select_option('private')
        with page.expect_response(lambda r: r.request.method == 'POST' and r.url == api + '/playlists') as response:
            page.locator('.create-card button.full-button').click()
        assert response.value.status in (200, 201)
        playlists.update(response.value.json())
        suite.state['playlist_id'] = playlists['playlistId']; suite.save()
        page.wait_for_url('**/playlists/' + playlists['playlistId'])
        expect(page.locator('.hero-copy h1')).to_contain_text(playlists['name'])
    suite.case(owner, 'U-PLAYLIST-CREATE-01', 'Tạo playlist private; tên trống không submit', playlist_create, expected='Playlist private persist; nút tạo disabled khi tên trống')

    if playlists:
        def playlist_edit():
            suite.go(owner, '/playlists/' + playlists['playlistId'], 'app-playlists-page')
            page.locator('.title-edit-button').click()
            page.locator('#edit-playlist-description').fill('Bộ sưu tập fixture E2E — đã chỉnh sửa')
            with page.expect_response(lambda r: r.request.method == 'PATCH' and r.url == api + '/playlists/' + playlists['playlistId']) as response:
                page.locator('form button[type=submit]').click()
            assert response.value.status == 200
            page.reload()
            expect(page.locator('.hero-description')).to_have_text('Bộ sưu tập fixture E2E — đã chỉnh sửa')
            assert suite.api(owner, 'get', '/playlists/' + playlists['playlistId']).json()['description'] == 'Bộ sưu tập fixture E2E — đã chỉnh sửa'
        suite.case(owner, 'U-PLAYLIST-EDIT-01', 'Sửa mô tả playlist và reload', playlist_edit, expected='PATCH 200; UI sau reload và API giữ mô tả')

        def private_access():
            response = suite.api(member, 'get', '/playlists/' + playlists['playlistId'])
            assert response.status in (403, 404)
        suite.case(member, 'U-PLAYLIST-ACCESS-01', 'Member không đọc playlist private của owner', private_access, expected='API 403/404; không trả nội dung private')

    routes = [
        ('HOME', '/home', 'app-home-page'), ('EXPLORE', '/explore', 'app-explore-page'),
        ('SUBSCRIPTIONS', '/subscriptions', 'app-subscriptions-page'),
        ('HISTORY', '/history', 'app-library-page'), ('LIKED', '/liked', 'app-library-page'),
        ('PLANS', '/plans', 'app-plans-page'), ('TERMS', '/terms', 'app-public-policy-page'),
        ('PRIVACY', '/privacy', 'app-public-policy-page'), ('GUIDELINES', '/guidelines', 'app-public-policy-page'),
        ('POLICIES', '/policies', 'app-public-policy-page'),
    ]
    for name, route, selector in routes:
        def open_route(route=route, selector=selector):
            suite.go(owner, route, selector)
            expect(page.locator(selector).locator('main, section').first).to_be_visible()
        suite.case(owner, 'U-' + name + '-SMOKE-01', 'Smoke route ' + route, open_route, expected='Component của route hiển thị', steps='Điều hướng trực tiếp; chờ component', data=route)

    def search_empty():
        suite.go(owner, '/search?q=hutube_e2e_no_such_video_0311', 'app-explore-page')
        expect(page.locator('.search-title')).to_contain_text('hutube_e2e_no_such_video_0311')
        expect(page.locator('.search-video-card')).to_have_count(0)
    suite.case(owner, 'U-DISCOVERY-EMPTY-01', 'Tìm kiếm từ khóa không tồn tại', search_empty, expected='Query hiển thị đúng, không có card dữ liệu giả')

    if channel:
        for name, route, selector in [
            ('OVERVIEW', '/studio/overview', 'app-studio-overview-page'),
            ('CONTENT', '/studio/content', 'app-studio-content-page'),
            ('ANALYTICS', '/studio/analytics', 'app-studio-analytics-page'),
            ('COMMENTS', '/studio/comments', 'app-studio-comments-page'),
            ('SUBTITLES', '/studio/subtitles', 'app-studio-subtitles-page'),
            ('SETTINGS', '/studio/settings', 'app-studio-settings-page'),
            ('INVITATIONS', '/studio/invitations', 'app-channel-invitations-page'),
        ]:
            suite.case(owner, 'U-STUDIO-' + name + '-SMOKE-01', 'Smoke route ' + route,
                       lambda route=route, selector=selector: suite.go(owner, route, selector) and None,
                       expected='Màn hình Studio đúng route và quyền owner', data=route)
