"""Existing-account registration boundaries, real cookie/session and logout flows."""
import re
from playwright.sync_api import expect

def run_negative(suite,owner,admin):
    for application,identity in [('user',owner),('admin',admin)]:
        guest=suite.actor('wrong-password-'+application,application,'guest')
        def wrong(case,guest=guest,identity=identity):
            page=guest['page']
            page.goto(guest['origin']+'/login')
            page.locator('#email').fill(identity['identity']['email'])
            page.locator('#password').fill('QC-Deliberately-Wrong-Password!')
            response=suite.response(guest,'/auth/login',lambda:page.locator('button[type=submit]').click(),method='POST',status=401)
            assert response.json()['code']=='INVALID_CREDENTIALS'
            expect(page.locator('[role=alert]')).to_be_visible()
            assert page.url.split('?')[0].endswith('/login')
            page.locator('#password').fill('')
            case['steps']=['One deliberately wrong password attempt for supplied email','Assert actual 401 INVALID_CREDENTIALS','Error stays on login; no authenticated route']
        suite.case(guest,'LIVE-AUTH-WRONG-PASSWORD-'+application.upper(),'AUTH-LOGIN-03' if application=='user' else 'AUTH-EXT-02','One wrong password '+application,'Wrong password is denied exactly once without entering a protected route',wrong,module='authentication')

def run(suite,owner,admin):
    guest=suite.actor('registration-guest','user','guest')
    page=guest['page']
    for kind in ['required','mismatch','duplicate']:
        def register(case,kind=kind):
            page.goto(guest['origin']+'/register')
            expect(page.locator('#username')).to_be_visible()
            if kind!='required':
                page.locator('#username').fill(owner['identity']['username'])
                page.locator('#email').fill(owner['identity']['email'])
                page.locator('#displayName').fill(owner['identity']['displayName'])
                page.locator('#password').fill('SyntheticNoAccount123!')
                page.locator('#confirmPassword').fill('DifferentNoAccount123!' if kind=='mismatch' else 'SyntheticNoAccount123!')
            before=sum(r['method']=='POST' and r['path']=='/api/v1/auth/register' for r in suite.report['http_statuses'])
            if kind=='duplicate':
                response=suite.response(guest,'/auth/register',lambda:page.locator('button[type=submit]').click(),method='POST',status=409)
                assert response.json()['code'] in ['EMAIL_ALREADY_EXISTS','USERNAME_ALREADY_EXISTS']
            else:
                page.locator('button[type=submit]').click()
                expect(page.locator('[role=alert]')).to_be_visible()
                after=sum(r['method']=='POST' and r['path']=='/api/v1/auth/register' for r in suite.report['http_statuses'])
                assert before==after
            expect(page).to_have_url(re.compile('/register(?:\\?|$)'))
            case['steps']=['Register → '+kind,'Check field/server error','Ensure no account creation or successful registration']
        parent={'required':'AUTH-REG-01','mismatch':'AUTH-REG-02','duplicate':'AUTH-REG-04'}[kind]
        suite.case(guest,'LIVE-AUTH-REGISTER-'+kind.upper(),parent,'Register '+kind,'Invalid registration cannot create another account',register,module='authentication')
    for application in ['user','admin']:
        actor=suite.actor('session-check-'+application,application)
        page=actor['page']
        def session(case,actor=actor,page=page,application=application):
            path='/account'
            suite.go(actor,path,'app-account-page','/account/profile' if application=='user' else '/auth/sessions')
            me=suite.api(actor,'get','/auth/me').json()
            assert me['userId']==actor['identity']['userId']
            cookies=actor['context'].cookies(actor['api_url']+'/auth/refresh')
            expected_name='hutube_refresh' if application=='user' else 'hutube_admin_refresh'
            assert any(c['name']==expected_name and c['httpOnly'] for c in cookies),'Correct platform refresh cookie must be HttpOnly'
            storage=page.evaluate('() => [...Object.entries(localStorage),...Object.entries(sessionStorage)]')
            assert not any(re.search(r'eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+',str(v)) for k,v in storage),'JWT must not be stored in browser storage'
            page.reload()
            expect(page.locator('app-account-page')).to_be_visible()
            assert suite.api(actor,'get','/auth/me').json()['userId']==me['userId']
            case['resource_ids']=[me['userId']]
            case['steps']=['Real UI login with supplied identity','Correct HttpOnly platform cookie','No JWT in local/session storage','Reload → same identity through API']
        suite.case(actor,'LIVE-AUTH-SESSION-'+application.upper(),'AUTH-LOGIN-04' if application=='user' else 'AUTH-ADMIN-02','Identity/cookie/reload '+application,'Same real identity restores and correct platform cookie remains HttpOnly',session,module='authentication')
        def logout(case,actor=actor,page=page,application=application):
            if application=='user':
                if page.locator('.top-avatar').get_attribute('aria-expanded')!='true':
                    page.locator('.top-avatar').click()
                page.locator('.account-drawer__logout').click()
                page.locator('app-feedback-host .confirm-cancel').click()
                expect(page.locator('app-feedback-host app-confirm-dialog')).to_have_count(0)
                assert suite.api(actor,'get','/auth/me').status==200
                if page.locator('.top-avatar').get_attribute('aria-expanded')!='true':
                    page.locator('.top-avatar').click()
                page.locator('.account-drawer__logout').click()
                suite.response(actor,'/auth/logout',lambda:page.locator('app-feedback-host .confirm-submit').click(),method='POST')
            else:
                suite.response(actor,'/auth/logout',lambda:page.locator('app-account-page .account-content > .section-heading > button').click(),method='POST')
            page.wait_for_url('**/login**')
            page.goto(actor['origin']+('/account' if application=='user' else '/users'))
            page.wait_for_url('**/login**')
            expect(page.locator('#email')).to_be_visible()
            suite.api(actor,'get','/auth/me',expected=401)
            case['steps']=['User cancel logout → session still valid' if application=='user' else 'Admin logout via account UI','Confirm real logout request','Protected route redirects to login','Old current-session token no longer authenticates']
        suite.case(actor,'LIVE-AUTH-LOGOUT-'+application.upper(),'AUTH-LOGIN-06' if application=='user' else 'AUTH-ADMIN-03','Logout and guard '+application,'Logout revokes this test session and protects direct routes',logout,module='authentication')
