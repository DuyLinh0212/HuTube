"""Actual interrupted authentication requests, duplicate-submit and redirect boundaries."""
from urllib.parse import urlsplit,quote
from playwright.sync_api import expect
from support.local_db import LocalDb
from flows.expanded.common import case,snapshot_module
from tests.full_functional import pickup_link

def run(suite,config,actors):
    snapshot_module(suite,__file__);db=LocalDb(config)
    def guest(label):
        actor=suite.actor('auth-fault-'+label,'user','guest');actor['api_url']=config['api_url'];return actor
    def fill_registration(actor,label):
        p=actor['page'];suite.go(actor,'/register','app-auth-page')
        email=('qc.authfault.'+label+'.'+suite.run_id+'@example.test').lower()
        for selector,value in [('#displayName','QC auth fault '+label),('#username','qc_af_'+label+'_'+suite.run_id[9:15]),
            ('#email',email),('#password','QCAuthFaultFixture2026!'),('#confirmPassword','QCAuthFaultFixture2026!')]:p.locator(selector).fill(value)
        p.locator('#confirmPassword').press('Tab');return email
    actor=guest('register-network')
    def register_network(entry):
        p=actor['page'];email=fill_registration(actor,'network');route='**/api/v1/auth/register'
        p.route(route,lambda request:request.abort('internetdisconnected'))
        try:
            p.locator('button[type=submit]').click();expect(p.locator('[role=alert]')).to_be_visible()
            assert db.account_count(email)==0
        finally:p.unroute(route)
        suite.response(actor,'/auth/register',lambda:p.locator('button[type=submit]').click(),method='POST',status=201)
        assert db.account_count(email)==1
        entry['steps']=['Abort actual registration network request','UI shows error, zero backend account created',
            'Restore network and retry same populated form','Actual 201 and exactly one persisted user; no fake success']
        entry['resource_ids']=[db.account(email)['user_id']]
    case(suite,actor,'AUTH-REGISTER-NETWORK-RETRY','AUTH-EXT-02','Interrupted registration retries once without ghost account',register_network,'authentication')
    suite.release_actor(actor)
    actor=guest('duplicate-submit')
    def duplicate(entry):
        p=actor['page'];email=fill_registration(actor,'duplicate');requests=[]
        def observed(req):
            if req.method=='POST' and urlsplit(req.url).path=='/api/v1/auth/register':requests.append(True)
        p.on('request',observed)
        try:
            def rapid():
                button=p.locator('button[type=submit]')
                if getattr(actor['context'],'_qc_touch_actions',False):
                    box=button.bounding_box();assert box
                    for _ in range(2):p.touchscreen.tap(box['x']+box['width']/2,box['y']+box['height']/2)
                else:button.dblclick()
            suite.response(actor,'/auth/register',rapid,method='POST',status=201)
            p.wait_for_timeout(500);assert len(requests)==1 and db.account_count(email)==1
        finally:p.remove_listener('request',observed)
        entry['steps']=['Fill all real registration inputs','Rapid double click or two genuine touch taps',
            'Busy state prevents duplicate POST','Exactly one real pending account persists']
        entry['resource_ids']=[db.account(email)['user_id']]
    case(suite,actor,'AUTH-REGISTER-DOUBLE-SUBMIT','AUTH-EXT-02','Repeated submit creates only one actual user',duplicate,'authentication')
    suite.release_actor(actor)
    actor=guest('login-network')
    def login_network(entry):
        p=actor['page'];suite.go(actor,'/login','app-auth-page')
        credentials=suite.credentials['member'];p.locator('#email').fill(credentials['email']);p.locator('#password').fill(credentials['password']);p.locator('#password').press('Tab')
        route='**/api/v1/auth/login';p.route(route,lambda request:request.abort('internetdisconnected'))
        try:
            p.locator('button[type=submit]').click();expect(p.locator('[role=alert]')).to_be_visible()
            suite.api(actor,'get','/auth/me',expected=401)
        finally:p.unroute(route)
        response=suite.response(actor,'/auth/login',lambda:p.locator('button[type=submit]').click(),method='POST')
        assert response.json()['user']['userId']==actors['member']['identity']['userId']
        p.wait_for_url('**/home');assert suite.api(actor,'get','/auth/me').json()['userId']==actors['member']['identity']['userId']
        entry['steps']=['Interrupt real login request','UI error and /auth/me 401; no authenticated success',
            'Restore request path and retry same form','Real 200, correct identity and protected session']
    case(suite,actor,'AUTH-LOGIN-NETWORK-RETRY','AUTH-EXT-02','Interrupted login cannot create false authenticated UI',login_network,'authentication')
    suite.release_actor(actor)
    for index,destination in enumerate(['https://example.test/escape','//example.test/escape','/%2Fexample.test/escape','/account']):
        actor=guest('return-'+str(index))
        def redirect(entry,destination=destination,actor=actor):
            p=actor['page'];suite.go(actor,'/login?returnUrl='+quote(destination,safe=''),'app-auth-page')
            credentials=suite.credentials['member'];p.locator('#email').fill(credentials['email']);p.locator('#password').fill(credentials['password']);p.locator('#password').press('Tab')
            suite.response(actor,'/auth/login',lambda:p.locator('button[type=submit]').click(),method='POST')
            expected='/account' if destination=='/account' else '/home';p.wait_for_url(actor['origin']+expected)
            assert urlsplit(p.url).netloc==urlsplit(actor['origin']).netloc
            entry['steps']=['Actual returnUrl query '+destination,'Login with verified ordinary Member',
                'Unsafe destination stays on local home; safe account destination is preserved']
        case(suite,actor,'AUTH-RETURN-URL-'+str(index),'AUTH-EXT-03','Authentication return URL boundary '+str(index),redirect,'authentication')
        suite.release_actor(actor)
    actor=guest('reset-expired')
    def reset_expired(entry):
        credentials=suite.credentials['member'];uid=actors['member']['identity']['userId']
        suite.api(actor,'post','/auth/forgot-password',data={'email':credentials['email']})
        link=pickup_link(config,credentials['email'],'reset-password')
        db.sql("UPDATE users SET password_reset_expires_at=now()-interval '1 second' WHERE user_id=:'uid'::uuid;",{'uid':uid})
        p=actor['page'];p.goto(link);expect(p.locator('#password')).to_be_visible()
        for name in ['password','confirmPassword']:p.locator('#'+name).fill('QCExpiredMustNotApply2026!')
        suite.response(actor,'/auth/reset-password',lambda:p.locator('button[type=submit]').click(),method='POST',status=400)
        expect(p.locator('[role=alert]')).to_be_visible();suite.api(actors['member'],'get','/auth/me')
        entry['resource_ids']=[uid];entry['fixture_preparation']='Only the existing synthetic Member reset expiry clock is set to past; password and result are not seeded'
        entry['steps']=['Real forgot request and recipient Pickup link','Expired fixture clock','Actual reset UI 400 with visible error','Existing authenticated Member remains valid']
    case(suite,actor,'AUTH-RESET-EXPIRED-NO-MUTATION','AUTH-EXT-03','Expired reset token cannot replace a password or revoke valid sessions',reset_expired,'authentication')
    suite.release_actor(actor)
    actor=guest('field-boundaries')
    for label,selector,value in [
        ('short-password','#password','Short123!'),
        ('password-no-uppercase','#password','lowercase12345!'),
        ('password-no-digit','#password','NoDigitsAllowed!'),
        ('username-short','#username','ab'),
        ('username-invalid','#username','qc space'),
        ('email-invalid','#email','qc-invalid-address'),
    ]:
        def boundary(entry,label=label,selector=selector,value=value):
            p=actor['page'];email=fill_registration(actor,'fields')
            p.locator(selector).fill(value)
            if selector=='#password':p.locator('#confirmPassword').fill(value)
            count=lambda:sum(e['method']=='POST' and e['path']=='/api/v1/auth/register' for e in suite.report['http_statuses'])
            before=count();p.locator('button[type=submit]').click()
            expect(p.locator(selector)).to_have_attribute('aria-invalid','true')
            expect(p.locator('[role=alert]')).to_be_visible();assert count()==before and db.account_count(email)==0
            entry['steps']=['Fill otherwise valid registration','Enter boundary '+label,'Submit actual UI → invalid field and visible error','No registration request or persisted account']
        case(suite,actor,'AUTH-FIELD-'+label.upper(),'AUTH-EXT-02','Registration field boundary '+label,boundary,'authentication')
    def normalized(entry):
        p=actor['page'];email=fill_registration(actor,'normalized')
        p.locator('#email').fill('  '+email.upper()+'  ')
        p.locator('#displayName').fill('  QC Unicode Đặng  ')
        suite.response(actor,'/auth/register',lambda:p.locator('button[type=submit]').click(),method='POST',status=201)
        assert db.account_count(email)==1;account=db.account(email)
        assert db.sql("SELECT email::text FROM users WHERE user_id=:'uid'::uuid;",{'uid':account['user_id']})==email
        # This second attempt is an actual duplicate request, not a seeded conflict.
        fill_registration(actor,'normalized2');p.locator('#email').fill(email.upper())
        result=suite.response(actor,'/auth/register',lambda:p.locator('button[type=submit]').click(),method='POST',status=409)
        assert result.json()['code']=='EMAIL_ALREADY_EXISTS' and db.account_count(email)==1
        entry['resource_ids']=[account['user_id']]
        entry['steps']=['Actual registration with uppercase email and surrounding spaces','Persisted email normalized to lowercase, one account','Submit same identity with uppercase email again','Actual 409 and account count remains exactly one']
    case(suite,actor,'AUTH-EMAIL-CASE-WHITESPACE-DUPLICATE','AUTH-EXT-02','Email normalization cannot create case variants',normalized,'authentication')
    def maximum(entry):
        p=actor['page'];email=fill_registration(actor,'maximum')
        password='Aa1'+('x'*126)
        p.locator('#password').fill('');p.locator('#password').press_sequentially(password)
        assert len(p.locator('#password').input_value())==128
        assert p.locator('#password').evaluate('(e)=>e.validity.valid')
        p.locator('#username').fill('');p.locator('#username').press_sequentially('q'*51)
        assert len(p.locator('#username').input_value())==50
        assert p.locator('#username').evaluate('(e)=>e.validity.valid')
        suite.api(actor,'post','/auth/register',data={'username':'qc_max_'+suite.run_id[9:15],
            'email':email,'displayName':'QC maximum boundary','password':password},expected=400)
        assert db.account_count(email)==0
        # Mask both controls because reveal is a real browser UI action.
        p.locator('#password').fill('');p.locator('#confirmPassword').fill('')
        entry['steps']=['Type 129 password characters with actual keyboard input; input caps at 128 and remains valid',
            'Type 51 username characters; input caps at 50','Bypass client cap with actual 129-character API registration → 400',
            'No persisted account for the rejected server boundary']
    case(suite,actor,'AUTH-REGISTRATION-MAX-LENGTH','AUTH-EXT-02','Client and backend enforce registration maximums',maximum,'authentication')
    suite.release_actor(actor)
