"""Visibility, cancel and deletion using a separate disposable playlist."""
from playwright.sync_api import expect


def run(suite, owner, member):
    page = owner['page']
    playlist_id = suite.state.get('playlist_id')
    if not playlist_id:
        return
    base = '/playlists/' + playlist_id
    original = suite.api(owner, 'get', base).json()

    def open_editor():
        suite.go(owner, base, 'app-playlists-page')
        page.locator('.title-edit-button').click()
        expect(page.locator('.playlist-modal--edit')).to_be_visible()

    def visibility():
        for value in ['unlisted', 'public', 'private']:
            open_editor()
            page.locator('#edit-playlist-visibility').select_option(value)
            with page.expect_response(lambda response: response.request.method == 'PATCH' and response.url.endswith(base)) as pending:
                page.locator('form button[type=submit]').click()
            assert pending.value.status == 200
            expect(page.locator('.playlist-modal--edit')).to_have_count(0)
            assert suite.api(owner, 'get', base).json()['visibility'] == value
            response = suite.api(member, 'get', base)
            if value == 'private':
                assert response.status in (403, 404)
            else:
                assert response.status == 200 and response.json()['playlistId'] == playlist_id
                suite.go(member, base, 'app-playlists-page')
                expect(member['page'].locator('.hero-copy h1')).to_have_text(response.json()['name'])
                expect(member['page'].locator('.title-edit-button')).to_have_count(0)
    try:
        suite.case(owner, 'U-PLAYLIST-VISIBILITY-01', 'Unlisted/public/private: quyền xem và sửa đúng actor', visibility,
                   expected='Owner PATCH 200; unlisted/public member đọc 200 không nút sửa; private 403/404')
    finally:
        # Preserve the prerequisite for later private-access assertions even if
        # an intermediate UI operation fails.
        assert suite.api(owner, 'patch', base, data={'name': original['name'],
            'description': original.get('description'), 'visibility': 'private'}).status == 200

    def cancel():
        original = suite.api(owner, 'get', base).json()
        open_editor()
        page.locator('#edit-playlist-name').fill('HuTube E2E — tên chưa lưu')
        page.locator('.playlist-modal--edit .modal-close').click()
        suite.go(owner, base, 'app-playlists-page')
        expect(page.locator('.hero-copy h1')).to_contain_text(original['name'])
        assert suite.api(owner, 'get', base).json()['name'] == original['name']
        page.locator('.title-edit-button').click()
        expect(page.locator('#edit-playlist-name')).to_have_value(original['name'])
        page.locator('.playlist-modal--edit .modal-close').click()
    suite.case(owner, 'U-PLAYLIST-CANCEL-01', 'Đóng modal không persist tên chưa lưu', cancel,
               expected='Reload/API giữ tên gốc')

    disposable = {}
    def delete():
        suite.go(owner, '/playlists', 'app-playlists-page')
        name = 'HuTube E2E — Playlist phụ kiểm thử xóa'
        stored = suite.api(owner, 'get', '/playlists')
        assert stored.status == 200
        disposable.update(next((item for item in stored.json() if item['name'] == name), {}))
        if not disposable:
            page.locator('#playlist-name').fill(name)
            page.locator('#playlist-visibility').select_option('private')
            with page.expect_response(lambda response: response.request.method == 'POST' and response.url.endswith('/playlists')) as pending:
                page.locator('.create-card button.full-button').click()
            assert pending.value.status in (200, 201)
            disposable.update(pending.value.json())
        target = '/playlists/' + disposable['playlistId']
        suite.go(owner, target, 'app-playlists-page')
        page.locator('.title-edit-button').click()
        page.once('dialog', lambda dialog: dialog.dismiss())
        page.locator('.text-danger-button').click()
        assert suite.api(owner, 'get', target).status == 200
        page.once('dialog', lambda dialog: dialog.accept())
        with page.expect_response(lambda response: response.request.method == 'DELETE' and response.url.endswith(target)) as pending:
            page.locator('.text-danger-button').click()
        assert pending.value.status == 204
        expect(page.locator('.create-card')).to_be_visible()
        assert suite.api(owner, 'get', target).status == 404
        assert suite.api(owner, 'get', base).status == 200
        assert suite.api(owner, 'get', '/videos/' + suite.state['video_id']).status == 200
    suite.case(owner, 'U-PLAYLIST-DELETE-01', 'Playlist phụ: cancel rồi delete; giữ playlist/video chính', delete,
               expected='Cancel giữ tài nguyên; DELETE 204 + GET 404; playlist/video chính vẫn GET 200')
