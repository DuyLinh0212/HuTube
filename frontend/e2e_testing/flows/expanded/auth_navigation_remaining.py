"""Previously unasserted consumed-verify history and Admin registration branches."""
from urllib.parse import urlsplit
from playwright.sync_api import expect
from flows.expanded.common import case,snapshot_module
from tests.full_functional import pickup_link
from support.local_db import LocalDb

def run(suite,config,actors):
    snapshot_module(suite,__file__);guest=suite.actor('verify-history-guest','user','guest');guest['api_url']=config['api_url'];p=guest['page'];db=LocalDb(config)
    owner=actors['owner'];uid=owner['identity']['userId'];email=owner['identity']['email']
    def database():
        return db.sql("SELECT json_build_object('verified',email_verified_at,'used',email_verification_used_at,'status',status) FROM users WHERE user_id=:'id'::uuid;",{'id':uid})
    try:
        def replay(entry):
            before=database();link=pickup_link(config,email,'verify-email')
            assert db.account(email)['verified']
            # This reuses a consumed real Pickup message, never re-sends a
            # successful verification that the user asked us not to rerun.
            response=suite.response(guest,'/auth/verify-email',lambda:p.goto(link),method='POST',status=400)
            expect(p.locator('[role=alert]')).to_be_visible();expect(p.locator('.notice.success')).to_have_count(0)
            assert database()==before and not any(c['name'] in ('hutube_refresh','hutube_admin_refresh') for c in guest['context'].cookies(config['api_url']+'/auth/refresh'))
            suite.go(guest,'/login','app-auth-page');p.go_back();expect(p.locator('[role=alert]')).to_be_visible()
            expect(p.locator('.notice.success')).to_have_count(0);assert urlsplit(p.url).path=='/verify-email' and database()==before
            p.go_forward();expect(p.locator('#email')).to_be_visible();assert urlsplit(p.url).path=='/login'
            p.go_back();expect(p.locator('[role=alert]')).to_be_visible();assert database()==before
            entry['resource_ids']=[uid];entry['steps']=['Reuse actual already-consumed recipient-specific verification mail; no new mail or successful auth rerun','Actual verify POST rejects replay 400 and preserves exact verified/used/status database values','No refresh cookie or false verification success','Real browser Back/Forward/Back keeps correct error/login routes and never consumes token again','Expired/invalid/missing tokens and unsafe return URLs are linked to their previous PASS evidence separately']
        case(suite,guest,'AUTH-CONSUMED-VERIFY-BROWSER-HISTORY','AUTH-EXT-03','Consumed verification cannot replay through browser history',replay,'authentication')
        admin_guest=suite.actor('admin-registration-guest','admin','guest');admin_guest['api_url']=config['api_url'];q=admin_guest['page']
        def admin_registration(entry):
            before=sum(v['method']=='POST' and v['path']=='/api/v1/auth/register' and v['actor']==admin_guest['name'] for v in suite.report['http_statuses'])
            q.goto(admin_guest['origin']+'/register');q.wait_for_url('**/login**');expect(q.locator('#email')).to_be_visible();expect(q.locator('#username')).to_have_count(0)
            q.reload();expect(q.locator('#username')).to_have_count(0);expect(q.locator('#email')).to_be_visible();assert urlsplit(q.url).path=='/login'
            after=sum(v['method']=='POST' and v['path']=='/api/v1/auth/register' and v['actor']==admin_guest['name'] for v in suite.report['http_statuses']);assert after==before
            entry['steps']=['Guest direct Admin /register route','Actual conditional route is absent; real wildcard/guard returns to login','Reload cannot render username/registration form','Zero registration POST; no privileged account/session created']
        try:case(suite,admin_guest,'AUTH-ADMIN-REGISTRATION-ROUTE-ABSENT','AUTH-EXT-03','Admin cannot expose self registration through direct URL or reload',admin_registration,'authentication')
        finally:suite.release_actor(admin_guest)
    finally:suite.release_actor(guest)
