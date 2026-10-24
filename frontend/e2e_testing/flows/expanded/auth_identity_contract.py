"""Explicit login/storage, restoration, and session deletion assertions."""
import re
from playwright.sync_api import expect
from flows.expanded.common import case,snapshot_module

def run(suite,config,actors):
    snapshot_module(suite,__file__)
    actor=suite.actor('auth-identity-contract','user','user');p=actor['page'];uid=actor['identity']['userId']
    try:
        def identity(entry):
            suite.go(actor,'/account','app-account-page','/account/profile')
            assert suite.api(actor,'get','/auth/me').json()['userId']==uid
            cookies=actor['context'].cookies(actor['api_url']+'/auth/refresh')
            assert any(c['name']=='hutube_refresh' and c['httpOnly'] for c in cookies)
            values=p.evaluate('()=>[...Object.values(localStorage),...Object.values(sessionStorage)]')
            password=suite.credentials['user']['password']
            assert not any(password in value or re.search(r'eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+',value) for value in values)
            entry['resource_ids']=[uid]
            entry['steps']=['Actual UI login returns the fixture identity','Account/me read-back matches same user ID','Refresh cookie is HttpOnly for real API path','Neither fixture password nor JWT occurs anywhere in local/session storage; values are not saved']
        case(suite,actor,'AUTH-LOGIN-IDENTITY-COOKIE-STORAGE','AUTH-LOGIN-04','Login restores exact identity without storing password/JWT',identity,'authentication')
        def reload(entry):
            p.reload();expect(p.locator('app-account-page')).to_be_visible()
            assert p.url.endswith('/account') and suite.api(actor,'get','/auth/me').json()['userId']==uid
            entry['resource_ids']=[uid];entry['steps']=['Reload actual protected account route','Session restores through actual backend','Account component remains and exact user ID is unchanged; no login redirect']
        case(suite,actor,'AUTH-RELOAD-IDENTITY-PROTECTED','AUTH-LOGIN-05','Reload retains the protected account and same identity',reload,'authentication')
        def logout(entry):
            p.locator('.top-avatar').click();p.locator('.account-drawer__logout').click();p.locator('.logout-confirm-cancel').click()
            assert suite.api(actor,'get','/auth/me').json()['userId']==uid
            if p.locator('.top-avatar').get_attribute('aria-expanded')!='true':p.locator('.top-avatar').click()
            p.locator('.account-drawer__logout').click()
            suite.response(actor,'/auth/logout',lambda:p.locator('.logout-confirm-submit').click(),method='POST')
            p.wait_for_url('**/login**')
            assert not any(c['name']=='hutube_refresh' for c in actor['context'].cookies(actor['api_url']+'/auth/refresh'))
            suite.api(actor,'get','/auth/me',expected=401)
            p.goto(actor['origin']+'/account');p.wait_for_url('**/login**');expect(p.locator('app-account-page')).to_have_count(0)
            entry['resource_ids']=[uid]
            entry['steps']=['Actual logout cancelled; account/session remains authenticated','Actual confirmation sends logout request','Refresh cookie removed; prior session JWT returns 401','Direct protected route redirects to login without rendering account']
        case(suite,actor,'AUTH-LOGOUT-CANCEL-COOKIE-SESSION-GUARD','AUTH-LOGIN-06','Logout deletes cookie/session and enforces direct-route guard',logout,'authentication')
    finally:suite.release_actor(actor)
