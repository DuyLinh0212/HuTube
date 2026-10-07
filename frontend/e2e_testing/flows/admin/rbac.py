"""RBAC group lifecycle and permission persistence, isolated unassigned fixture."""
from playwright.sync_api import expect


def run(suite, admin, member):
    page, role = admin['page'], {}
    code = 'hutube_e2e_custom'
    permission = 'taxonomy.manage'
    changed_permissions = {}

    def open_roles():
        suite.go(admin, '/roles', 'app-admin-rbac-page')
        expect(page.locator('.role-list')).to_be_visible()

    def select_role():
        page.locator('.role-browser input[type=search]').fill(code)
        page.locator('.role-card').click()
        expect(page.locator('.role-summary')).to_contain_text(code)

    def create():
        open_roles()
        response = suite.api(admin, 'get', '/admin/roles')
        assert response.status == 200
        role.update(next((item for item in response.json() if item['code'] == code and item['status'] != 'deleted'), {}))
        if role:
            select_role()
            return 'reused'
        page.locator('.heading-actions .primary-action').click()
        dialog = page.locator('[role=dialog]')
        inputs = dialog.locator('input:not([type=checkbox])')
        inputs.nth(0).fill('HuTube E2E — Quyền tùy chỉnh')
        inputs.nth(1).fill(code)
        expect(dialog.locator('footer .primary-action')).to_be_disabled()
        dialog.locator('.permission-picker label').filter(has_text=permission).locator('input').check()
        inputs.nth(2).fill('Kiểm thử nhóm quyền fixture E2E')
        with page.expect_response(lambda r: r.request.method == 'POST' and r.url.endswith('/admin/roles')) as pending:
            dialog.locator('footer .primary-action').click()
        assert pending.value.status in (200,201)
        role.update(pending.value.json())
        assert role['permissions'] == [permission] and role['assignedUserCount'] == 0
        expect(dialog).to_have_count(0)
        suite.state['role_id'] = role['roleId']; suite.save()
    suite.case(admin, 'A-RBAC-CREATE-01', 'Tạo nhóm quyền; bắt buộc lý do', create,
               expected='Không submit khi thiếu reason; nhóm không phải system, có đúng permission')

    if not role:
        return

    def edit_cancel_save():
        open_roles(); select_role()
        baseline = next(item for item in suite.api(admin, 'get', '/admin/roles').json() if item['roleId'] == role['roleId'])
        original_granted = permission in baseline['permissions']
        page.locator('.matrix-actions .secondary-action').click()
        target = page.locator('.permission-row').filter(has_text=permission)
        target.click()
        expect(page.locator('.save-drawer .primary-action')).to_be_disabled()
        page.locator('.save-drawer .secondary-action').click()
        stored = next(item for item in suite.api(admin, 'get', '/admin/roles').json() if item['roleId'] == role['roleId'])
        assert (permission in stored['permissions']) == original_granted
        page.locator('.matrix-actions .secondary-action').click()
        target.click()
        page.locator('.save-drawer input').fill('Kiểm thử thu hồi permission fixture')
        with page.expect_response(lambda r: r.request.method == 'PUT' and r.url.endswith('/admin/roles/' + role['roleId'])) as pending:
            page.locator('.save-drawer .primary-action').click()
        assert pending.value.status == 200
        open_roles(); select_role()
        target = page.locator('.permission-row').filter(has_text=permission)
        if original_granted:
            expect(target).not_to_have_class(__import__('re').compile(r'is-granted'))
        else:
            expect(target).to_have_class(__import__('re').compile(r'is-granted'))
        stored = next(item for item in suite.api(admin, 'get', '/admin/roles').json() if item['roleId'] == role['roleId'])
        assert (permission in stored['permissions']) != original_granted
        changed_permissions['value'] = stored['permissions']
    suite.case(admin, 'A-RBAC-EDIT-01', 'Cancel rồi lưu thu hồi permission, reload', edit_cancel_save,
               expected='Cancel giữ permission; PUT có reason persist việc thu hồi')

    def denied():
        response = suite.api(member, 'put', '/admin/roles/' + role['roleId'], data={'name':'Forbidden role','description':None,'permissionCodes':[permission],'reason':'Forbidden change'})
        assert response.status == 403
        stored = next(item for item in suite.api(admin, 'get', '/admin/roles').json() if item['roleId'] == role['roleId'])
        assert stored['name'] == role['name'] and stored['permissions'] == changed_permissions.get('value', role['permissions'])
    suite.case(member, 'X-RBAC-ACCESS-01', 'User không cấp permission Admin qua API', denied,
               module='access', expected='403; nhóm quyền không bị thay đổi')
