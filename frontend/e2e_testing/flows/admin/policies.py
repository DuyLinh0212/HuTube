"""Policy publishing via Admin UI, plus public API version synchronization."""
from playwright.sync_api import expect


def run(suite, admin, member):
    page,policy=admin['page'],{}
    code='HUTUBE_E2E_POLICY'
    content='Chính sách fixture E2E: nội dung kỹ thuật phải có mô tả nguồn rõ ràng.'
    updated=content+' Phiên bản cập nhật 2.0.'

    def open_policies():
        suite.go(admin,'/policies','app-admin-policies-page')
        expect(page.locator('.data-table')).to_be_visible()

    def create():
        open_policies()
        response=suite.api(admin,'get','/admin/policies')
        assert response.status==200
        policy.update(next((item for item in response.json() if item['code']==code),{}))
        if policy:
            page.locator('.search-wrap input').fill(code)
            expect(page.locator('tbody tr')).to_contain_text(code)
            return 'reused'
        page.locator('.header-actions .btn-primary').click()
        dialog=page.locator('.modal-dialog.modal-md')
        inputs=dialog.locator('input[type=text]')
        inputs.nth(0).fill(code)
        inputs.nth(1).fill('HuTube E2E — Chính sách nguồn nội dung')
        dialog.locator('select').nth(0).select_option('guidelines')
        dialog.locator('select').nth(1).select_option('info')
        inputs.nth(2).fill('1.0')
        dialog.locator('textarea').fill(content)
        with page.expect_response(lambda response:response.request.method=='POST' and response.url.endswith('/admin/policies')) as pending:
            dialog.locator('.modal-footer .btn-primary').click()
        assert pending.value.status in (200,201)
        policy.update(pending.value.json())
        assert policy['code']==code and policy['version']=='1.0' and policy['status']=='published'
        expect(dialog).to_have_count(0)
        suite.state['policy_id']=policy['policyId'];suite.save()
    suite.case(admin,'A-POLICY-CREATE-01','Tạo policy published v1 qua UI',create,
               expected='Code/group/severity/content/version persist đúng fixture')

    if not policy:
        return

    def publish():
        open_policies()
        page.locator('.search-wrap input').fill(code)
        row=page.locator('tbody tr').filter(has_text=code)
        if policy['version']=='2.0':
            expect(row.locator('.version-badge')).to_have_text('v2.0')
            assert policy['content']==updated
            return 'reused'
        row.locator('button').click()
        dialog=page.locator('.modal-dialog')
        dialog.locator('.version-update-card input').fill('2.0')
        dialog.locator('textarea').fill(updated)
        with page.expect_response(lambda response:response.request.method=='PUT' and response.url.endswith('/admin/policies/'+policy['policyId']+'/publish')) as pending:
            dialog.locator('.modal-footer .btn-primary').click()
        assert pending.value.status==200
        expect(dialog).to_have_count(0)
        open_policies()
        page.locator('.search-wrap input').fill(code)
        expect(page.locator('tbody tr .version-badge')).to_have_text('v2.0')
        stored=next(item for item in suite.api(admin,'get','/admin/policies').json() if item['code']==code)
        assert stored['version']=='2.0' and stored['content']==updated
    suite.case(admin,'A-POLICY-PUBLISH-01','Publish v2 và reload Admin',publish,
               expected='PUT publish 200; current version/content v2 persist')

    def public_api():
        suite.go(member,'/policies','app-public-policy-page')
        response=suite.api(member,'get','/policies')
        assert response.status==200
        stored=next(item for item in response.json() if item['code']==code)
        assert stored['version']=='2.0' and stored['content']==updated and stored['status']=='published'
        denied=suite.api(member,'put','/admin/policies/'+policy['policyId']+'/publish',data={
            'name':stored['name'],'group':stored['group'],'severity':stored['severity'],
            'status':'published','version':'3.0','content':'Forbidden policy mutation'})
        assert denied.status==403
    suite.case(member,'X-POLICY-API-01','API public đọc v2; User không publish Admin policy',public_api,
               module='policy',expected='Public API version/content v2; mutation Admin 403; chưa xác nhận nội dung động trong UI User')
