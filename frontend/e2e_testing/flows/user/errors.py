"""Clearly labeled fault injection; never substitutes for real backend flows."""
from playwright.sync_api import expect


def run(suite, owner):
    page=owner['page']
    pattern=suite.config['api_url']+'/videos/search*'
    def search_failure():
        page.route(pattern,lambda route:route.fulfill(status=500,content_type='application/json',body='{"code":"E2E_INJECTED_FAILURE"}'))
        try:
            suite.go(owner,'/search?q=hutube_e2e_fault','app-explore-page')
            expect(page.locator('.state-card--error[role=alert]')).to_be_visible()
            expect(page.locator('.search-video-card')).to_have_count(0)
        finally:
            page.unroute(pattern)
        with page.expect_response(lambda response:response.request.method=='GET' and '/videos/search' in response.url) as pending:
            page.locator('.state-card--error button').click()
        assert pending.value.status==200
        expect(page.locator('.state-card--error')).to_have_count(0)
    suite.case(owner,'X-ERROR-SEARCH-01','Fault injection 500 → retry API thật',search_failure,
               module='errors',data='Injected response 500 for videos/search only',
               expected='UI báo lỗi và không có card giả; bỏ injection, retry 200 và error biến mất')
