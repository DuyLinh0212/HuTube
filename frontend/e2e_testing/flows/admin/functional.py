"""Admin Web cases, separate from User cases and personal accounts."""
from urllib.parse import urlsplit
from playwright.sync_api import expect


def run(suite, admin, owner):
    page = admin['page']
    routes = [
        ('USERS', '/users', 'app-admin-users-page'), ('CHANNELS', '/channels', 'app-admin-channels-page'),
        ('VIDEOS', '/videos', 'app-admin-videos-page'), ('RBAC', '/roles', 'app-admin-rbac-page'),
        ('PLANS', '/plans', 'app-admin-plans-page'), ('SUBSCRIPTIONS', '/subscriptions', 'app-admin-subscriptions-page'),
        ('PAYMENTS', '/payments', 'app-admin-payments-page'), ('TOPICS', '/topics', 'app-admin-topics-page'),
        ('POLICY', '/policies', 'app-admin-policies-page'), ('MODERATION', '/moderation/videos', 'app-admin-moderation-page'),
        ('REPORTS', '/moderation/reports', 'app-admin-reports-page'), ('APPEALS', '/moderation/appeals', 'app-admin-appeals-page'),
        ('STRIKES', '/moderation/strikes', 'app-admin-strikes-page'),
        ('NOTIFICATIONS', '/system/notifications', 'app-system-notifications-page'),
        ('SYSTEM-REPORTS', '/system/reports', 'app-system-reports-page'), ('LOGS', '/system/logs', 'app-system-logs-page'),
        ('RECOMMENDATION', '/recommendations', 'app-recommendations-page'),
    ]
    for name, route, selector in routes:
        def open_route(route=route, selector=selector):
            suite.go(admin, route, selector)
            expect(page.locator(selector)).to_be_visible()
        suite.case(admin, 'A-' + name + '-SMOKE-01', 'Smoke route ' + route, open_route,
                   expected='Component đúng route; super admin được truy cập', steps='Điều hướng trực tiếp và chờ component', data=route)

    def user_search():
        suite.go(admin, '/users', 'app-admin-users-page')
        with page.expect_response(lambda r: r.request.method == 'GET' and urlsplit(r.url).path == '/api/v1/admin/users' and owner['email'] in r.url) as response:
            page.locator('input[type=search]').fill(owner['email'])
        assert response.value.status == 200
        expect(page.locator('.user-row')).to_have_count(1)
        expect(page.locator('.user-row')).to_contain_text(owner['email'])
        page.locator('.user-row').click()
        expect(page.locator('.detail-identity')).to_contain_text(owner['user_id'])
    suite.case(admin, 'A-USERS-SEARCH-01', 'Tìm owner và mở đúng detail', user_search,
               expected='Một row đúng email; detail chứa đúng user ID', steps='Nhập email fixture; chọn row; đối chiếu detail')

    def filters():
        suite.go(admin, '/users', 'app-admin-users-page')
        selections = page.locator('.filter-field select')
        for index in range(selections.count()):
            select = selections.nth(index)
            values = select.locator('option').evaluate_all('(options) => options.map(option => option.value)')
            for value in values:
                if value == select.input_value():
                    continue
                with page.expect_response(lambda r: r.request.method == 'GET' and urlsplit(r.url).path == '/api/v1/admin/users') as response:
                    select.select_option(value)
                assert response.value.status == 200
            select.select_option(values[0])
    suite.case(admin, 'A-USERS-FILTER-01', 'Chạy từng lựa chọn status và role', filters,
               expected='Mỗi lựa chọn gọi API users thành công; không lỗi JavaScript')
