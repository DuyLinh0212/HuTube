"""Auth validation, token errors, guest guards and isolated session logout."""
from urllib.parse import urlsplit
from playwright.sync_api import expect

def run(suite, owner, admin):
    for application in ['user','admin']:
        guest=suite.actor('guest-'+application,application,'guest')
        page=guest['page']
        for kind in ['required','invalid-email','show-hide']:
            def validation(case,kind=kind,page=page,guest=guest):
                page.goto(guest['origin']+'/login')
                expect(page.locator('#email')).to_be_visible()
                before=len([r for r in suite.report['http_statuses'] if r['actor']==guest['name'] and r['method']=='POST' and r['path']=='/api/v1/auth/login'])
                if kind=='required':
                    page.locator('button[type=submit]').click()
                    expect(page.locator('#email')).to_have_attribute('aria-invalid','true')
                    expect(page.locator('#password')).to_have_attribute('aria-invalid','true')
                elif kind=='invalid-email':
                    page.locator('#email').fill('invalid-address')
                    page.locator('#password').fill('SyntheticNoSubmit123!')
                    page.locator('button[type=submit]').click()
                    expect(page.locator('#email')).to_have_attribute('aria-invalid','true')
                else:
                    page.locator('#password').fill('SyntheticNoSubmit123!')
                    expect(page.locator('#password')).to_have_attribute('type','password')
                    page.locator('.reveal').click()
                    expect(page.locator('#password')).to_have_attribute('type','text')
                    expect(page.locator('.reveal')).to_have_attribute('aria-pressed','true')
                    page.locator('.reveal').click()
                    expect(page.locator('#password')).to_have_attribute('type','password')
                after=len([r for r in suite.report['http_statuses'] if r['actor']==guest['name'] and r['method']=='POST' and r['path']=='/api/v1/auth/login'])
                assert before==after, 'Validation must not submit login'
                case['steps']=['Login → '+kind,'Assert field/error state and zero login requests']
            suite.case(guest,application.upper()+'-AUTH-'+kind.upper(),'AUTH-EXT-02',application+' login '+kind,'Client validation/reveal behaves correctly and never logs in',validation,module='authentication')

        for route in ['/verify-email','/verify-email?token=invalid-qc-token','/reset-password?token=invalid-qc-token']:
            def token(case,route=route,page=page,guest=guest):
                page.goto(guest['origin']+route)
                expect(page.locator('app-auth-page')).to_be_visible()
                if route.startswith('/verify-email?'):
                    expect(page.locator('[role=alert]')).to_be_visible(timeout=30000)
                    expect(page.locator('[role=status]')).to_have_count(0)
                elif route=='/verify-email':
                    expect(page.locator('#resendEmail')).to_be_visible()
                    page.locator('button[type=submit]').click()
                    expect(page.locator('#resendEmail')).to_have_class(__import__('re').compile('ng-invalid'))
                    assert not page.locator('#resendEmail').evaluate('(e)=>e.validity.valid')
                else:
                    page.locator('button[type=submit]').click()
                    expect(page.locator('#password')).to_have_attribute('aria-invalid','true')
                assert urlsplit(page.url).path in ('/verify-email','/reset-password')
                case['steps']=['Open missing/invalid token route','Assert error or required fields','Ensure no false verification/reset success']
            suite.case(guest,application.upper()+'-AUTH-TOKEN-'+str(['/verify-email','/verify-email?token=invalid-qc-token','/reset-password?token=invalid-qc-token'].index(route)+1),'AUTH-EXT-03',application+' '+route.split('?')[0]+' invalid/missing token','Invalid token/missing input cannot produce success or authenticated state',token,module='authentication')

        routes=['/account','/playlists','/studio/upload'] if application=='user' else ['/users','/roles','/moderation/reports']
        for route in routes:
            def guard(case,route=route,page=page,guest=guest):
                page.goto(guest['origin']+route)
                page.wait_for_url('**/login**')
                expect(page.locator('#email')).to_be_visible()
                expect(page.locator('app-admin-users-page,app-account-page,app-playlists-page,app-video-upload-wizard')).to_have_count(0)
                case['steps']=['Guest direct navigation to '+route,'Assert login guard and absence of protected component']
            suite.case(guest,application.upper()+'-AUTH-GUARD-'+route.strip('/').replace('/','-').upper(),'X-ACCESS','Guest guard '+route,'Unauthenticated guest cannot render protected data',guard,module='authentication')
