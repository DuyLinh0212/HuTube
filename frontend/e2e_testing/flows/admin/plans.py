"""Plan UI CRUD and public catalog synchronization, without real payments."""
from playwright.sync_api import expect


def run(suite, admin, member):
    page = admin['page']
    plan = {}
    code = 'hutube_e2e_functional'

    def open_plans():
        suite.go(admin, '/plans', 'app-admin-plans-page')
        expect(page.locator('.plan-table')).to_be_visible()

    def matching_row():
        return page.locator('tbody tr').filter(has=page.locator('.plan-name small').filter(has_text=code))

    def create():
        open_plans()
        result = suite.api(admin, 'get', '/admin/plans')
        assert result.status == 200
        existing = next((item for item in result.json() if item['code'] == code), None)
        if existing:
            plan.update(existing)
            expect(matching_row()).to_contain_text(existing['name'])
            return 'reused'
        page.locator('.heading-actions .primary-action').click()
        page.locator('[name=code]').fill(code)
        page.locator('[name=name]').fill('HuTube E2E — Gói kiểm thử')
        page.locator('[name=description]').fill('Gói fixture E2E, không chuyển tiền thật.')
        for field, value in [('price','0'),('durationDays','30'),('storageLimit','20'),('maxUploadSize','1'),('maxVideoDuration','15'),('maxMembers','2')]:
            page.locator('[name=' + field + ']').fill(value)
        expect(page.locator('[name=isDefaultForNewUsers]')).not_to_be_checked()
        with page.expect_response(lambda r: r.request.method == 'POST' and r.url.endswith('/admin/plans')) as pending:
            page.locator('[role=dialog] button[type=submit]').click()
        assert pending.value.status in (200,201)
        plan.update(pending.value.json())
        expect(page.locator('[role=dialog]')).to_have_count(0)
        assert plan['storageLimit'] == 20 * 1024**3
        assert plan['maxVideoDuration'] == 15 * 60
        assert plan['isDefaultForNewUsers'] is False
        suite.state['plan_id'] = plan['planId']; suite.save()
    suite.case(admin, 'A-PLANS-CREATE-01', 'Tạo gói và kiểm tra chuyển đổi đơn vị', create,
               expected='GB → bytes, phút → giây; không thay gói mặc định của account mới')

    if not plan:
        return

    def edit():
        open_plans()
        matching_row().locator('.icon-action:not(.danger)').click()
        expect(page.locator('[name=code]')).to_be_disabled()
        page.locator('[name=description]').fill('Mô tả gói đã sửa — E2E')
        page.locator('[name=status]').select_option('active')
        with page.expect_response(lambda r: r.request.method == 'PUT' and r.url.endswith('/admin/plans/' + plan['planId'])) as pending:
            page.locator('[role=dialog] button[type=submit]').click()
        assert pending.value.status == 200
        expect(page.locator('[role=dialog]')).to_have_count(0)
        open_plans()
        stored = next(item for item in suite.api(admin, 'get', '/admin/plans').json() if item['planId'] == plan['planId'])
        assert stored['description'] == 'Mô tả gói đã sửa — E2E' and stored['status'] == 'active'
        assert stored['storageLimit'] == 20 * 1024**3 and stored['maxVideoDuration'] == 900
    suite.case(admin, 'A-PLANS-EDIT-01', 'Sửa gói, reload giữ quota và duration', edit,
               expected='Thông tin persist; code không sửa; không chuyển đổi đơn vị lần thứ hai')

    def public_catalog():
        suite.go(member, '/plans', 'app-plans-page')
        member['page'].locator('.plans-view-switch button').nth(1).click()
        response = suite.api(member, 'get', '/plans')
        assert response.status == 200
        assert any(item['planId'] == plan['planId'] for item in response.json())
        expect(member['page'].locator('app-plans-page')).to_contain_text('HuTube E2E — Gói kiểm thử')
    suite.case(member, 'X-PLANS-CATALOG-01', 'Gói active Admin xuất hiện ở User', public_catalog,
               module='plans', expected='Catalog UI và API cùng plan ID active')

    def archive():
        open_plans()
        page.once('dialog', lambda dialog: dialog.dismiss())
        matching_row().locator('.danger').click()
        assert any(item['planId'] == plan['planId'] for item in suite.api(member, 'get', '/plans').json())
        page.once('dialog', lambda dialog: dialog.accept())
        with page.expect_response(lambda r: r.request.method == 'POST' and r.url.endswith('/admin/plans/' + plan['planId'] + '/archive')) as pending:
            matching_row().locator('.danger').click()
        assert pending.value.status in (200,204)
        open_plans()
        stored = next(item for item in suite.api(admin, 'get', '/admin/plans').json() if item['planId'] == plan['planId'])
        assert stored['status'] == 'archived'
        assert not any(item['planId'] == plan['planId'] for item in suite.api(member, 'get', '/plans').json())
        suite.go(member, '/plans', 'app-plans-page')
        member['page'].locator('.plans-view-switch button').nth(1).click()
        expect(member['page'].locator('app-plans-page')).not_to_contain_text('HuTube E2E — Gói kiểm thử')
    suite.case(admin, 'A-PLANS-ARCHIVE-01', 'Cancel rồi archive; đối chiếu catalog User', archive,
               expected='Cancel giữ active; archive persist và gói biến mất khỏi catalog')
