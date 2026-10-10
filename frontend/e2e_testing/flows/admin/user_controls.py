"""Lock/unlock synthetic member via Admin UI and verify effect on User session."""
from playwright.sync_api import expect


def run(suite, admin, member):
    page=admin['page']
    base='/admin/users/'+member['user_id']
    reason='HuTube E2E — kiểm tra khóa thành viên fixture'

    def detail():
        suite.go(admin,'/users','app-admin-users-page')
        page.locator('input[type=search]').fill(member['email'])
        row=page.locator('.user-row').filter(has_text=member['email'])
        expect(row).to_have_count(1)
        row.click()
        expect(page.locator('.detail-identity')).to_contain_text(member['user_id'])

    def lock():
        detail()
        page.locator('.detail-actions .link-action.danger').click()
        expect(page.locator('.action-modal button[type=submit]')).to_be_disabled()
        page.locator('.action-modal [name=actionReason]').fill(reason)
        page.locator('.action-modal footer .secondary-button').click()
        assert suite.api(admin,'get',base).json()['status']=='active'
        page.locator('.detail-actions .link-action.danger').click()
        page.locator('.action-modal [name=actionReason]').fill(reason)
        with page.expect_response(lambda response:response.request.method=='POST' and response.url.endswith(base+'/lock')) as pending:
            page.locator('.action-modal button[type=submit]').click()
        assert pending.value.status==200 and pending.value.json()['status']=='banned'
        expect(page.locator('.action-modal')).to_have_count(0)
        stored=suite.api(admin,'get',base).json()
        assert stored['status']=='banned' and any(item['reason']==reason for item in stored['auditHistory'])
        assert suite.api(member,'get','/account/profile').status in (401,403)
        member['page'].goto(suite.config['user_url']+'/account')
        expect(member['page'].locator('#email')).to_be_visible(timeout=45000)
    try:
        suite.case(admin,'A-USERS-LOCK-01','Cancel rồi khóa member; User mất quyền truy cập',lock,
                   expected='Reason bắt buộc; cancel giữ active; banned persist/audit; session User bị chặn')
    finally:
        def unlock():
            current=suite.api(admin,'get',base)
            assert current.status==200
            if current.json()['status']!='active':
                detail()
                page.locator('.detail-actions .link-action.success').click()
                page.locator('.action-modal [name=actionReason]').fill('HuTube E2E — phục hồi member sau kiểm thử')
                with page.expect_response(lambda response:response.request.method=='POST' and response.url.endswith(base+'/unlock')) as pending:
                    page.locator('.action-modal button[type=submit]').click()
                assert pending.value.status==200 and pending.value.json()['status']=='active'
                expect(page.locator('.action-modal')).to_have_count(0)
            assert suite.api(admin,'get',base).json()['status']=='active'
            target=member['page']
            target.goto(suite.config['user_url']+'/login')
            expect(target.locator('#email')).to_be_visible(timeout=45000)
            target.locator('#email').fill(member['email'])
            target.locator('#password').fill('HuTubeWebE2e2026!')
            with target.expect_response(lambda response:response.request.method=='POST' and response.url.endswith('/auth/login')) as pending:
                target.locator('button[type=submit]').click()
            assert pending.value.status==200
            # User login now lands on Home by design; navigate to the
            # protected account page before asserting the restored identity.
            expect(target.locator('app-home-page')).to_be_visible(timeout=45000)
            target.goto(suite.config['user_url']+'/account')
            expect(target.locator('app-account-page')).to_be_visible(timeout=45000)
            expect(target.locator('.channel-display-name')).to_have_text(member['identity']['displayName'])
            assert suite.api(member,'get','/account/profile').status==200
        suite.case(admin,'A-USERS-UNLOCK-01','Unlock fixture và User đăng nhập lại',unlock,
                   expected='Active persist; session mới vào Account đúng identity; không reset status bằng SQL')
