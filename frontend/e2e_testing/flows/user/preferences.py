"""Account settings persist via UI; originals restored on the synthetic actor."""
from playwright.sync_api import expect


def run(suite, owner):
    page = owner['page']

    def open_tab(index):
        target = '/account/notifications' if index == 1 else '/account/settings'
        with page.expect_response(lambda r: r.request.method == 'GET' and r.url.endswith(target)) as loaded:
            suite.go(owner, '/account', 'app-account-page')
        assert loaded.value.status == 200
        expect(page.locator('.channel-display-name')).to_be_visible()
        page.locator('.settings-nav-list button').nth(index).click()

    def notifications():
        open_tab(1)
        response = suite.api(owner, 'get', '/account/notifications')
        assert response.status == 200
        original = response.json()
        keys = ['inAppEnabled', 'emailEnabled', 'newVideoEnabled', 'commentReplyEnabled', 'mentionEnabled', 'channelActivityEnabled']
        try:
            toggles = page.locator('.switches-vertical-list input[type=checkbox]')
            expect(toggles).to_have_count(len(keys))
            for index, key in enumerate(keys):
                page.locator('.switches-vertical-list .yt-switch').nth(index).click()
                expect(toggles.nth(index)).to_be_checked(checked=not original[key])
            with page.expect_response(lambda r: r.request.method == 'PUT' and r.url.endswith('/account/notifications')) as pending:
                page.locator('.form-buttons .btn-yt-primary').click()
            assert pending.value.status == 200
            open_tab(1)
            updated = suite.api(owner, 'get', '/account/notifications').json()
            for index, key in enumerate(keys):
                assert updated[key] is not original[key]
                expect(page.locator('.switches-vertical-list input[type=checkbox]').nth(index)).to_be_checked(checked=not original[key])
        finally:
            assert suite.api(owner, 'put', '/account/notifications', data=original).status == 200
        open_tab(1)
        restored = suite.api(owner, 'get', '/account/notifications').json()
        assert restored == original
    suite.case(owner, 'U-ACCOUNT-NOTIFICATIONS-01', 'Đổi sáu lựa chọn thông báo, reload và phục hồi', notifications,
               module='account', expected='UI/GET persist mọi lựa chọn; các flag khác không mất; phục hồi baseline')

    def privacy():
        open_tab(3)
        original = suite.api(owner, 'get', '/account/settings').json()
        checkbox = page.locator('.privacy-toggle-group input[type=checkbox]').first
        try:
            with page.expect_response(lambda r: r.request.method == 'PUT' and r.url.endswith('/account/settings')) as pending:
                page.locator('.privacy-toggle-group .yt-switch').first.click()
            assert pending.value.status == 200
            open_tab(3)
            expect(checkbox).to_be_checked(checked=not original['keepSubscriptionsPrivate'])
            current = suite.api(owner, 'get', '/account/settings').json()
            assert current['keepSubscriptionsPrivate'] is not original['keepSubscriptionsPrivate']
            assert current['theme'] == original['theme'] and current['language'] == original['language']
        finally:
            assert suite.api(owner, 'put', '/account/settings', data=original).status == 200
        open_tab(3)
        expect(checkbox).to_be_checked(checked=original['keepSubscriptionsPrivate'])
    suite.case(owner, 'U-ACCOUNT-PRIVACY-01', 'Đổi quyền riêng tư subscription và phục hồi', privacy,
               module='account', expected='PUT persist; không thay theme/language; phục hồi baseline')
