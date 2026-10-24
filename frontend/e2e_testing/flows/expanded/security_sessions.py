import re
from playwright.sync_api import expect
from support.local_db import LocalDb
from flows.expanded.common import snapshot_module
from flows.expanded.security_plan_common import identity, freeze, refresh, denied, stepcase, remember_refresh

def run(suite,config,actors):
    snapshot_module(suite,__file__)
    from support.actor_readiness import ensure_actor_pages
    ensure_actor_pages(suite,actors,['admin','member'])
    admin,foreign=actors['admin'],actors['member'];db=LocalDb(config)
    uid=identity(suite,config,'g1_priv')
    role=suite.api(admin,'post','/admin/roles',data={'code':'qc_sec_'+suite.run_id[9:15],
        'name':'QC dual-platform fixture','permissionCodes':['taxonomy.manage','user.view'],
        'reason':'Prepare isolated session/permission fixture'},expected=201).json()
    suite.api(admin,'put','/admin/users/'+uid+'/role',data={'roleCode':role['code'],'reason':'QC independent session actor'})
    web=suite.actor('g1-web','user','g1_priv')
    app=suite.actor('g1-admin-tab','admin','g1_priv',page=web['context'].new_page())
    try:
        def cookies(entry):
            assert suite.api(web,'get','/auth/me').json()['userId']==uid
            assert suite.api(app,'get','/admin/me').json()['userId']==uid
            items=web['context'].cookies()
            for name in ['hutube_refresh','hutube_admin_refresh']:
                cookie=next(c for c in items if c['name']==name)
                assert cookie['httpOnly'] and cookie['path']=='/api/v1/auth'
            currents=[]
            for actor in [web,app]:
                sessions=suite.api(actor,'get','/auth/sessions').json()['items']
                current=next(s for s in sessions if s['isCurrent']);currents.append(current)
                stores=actor['page'].evaluate('()=>[...Object.values(localStorage),...Object.values(sessionStorage)]')
                assert all(not re.search(r'eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.',s) and suite.credentials['g1_priv']['password'] not in s for s in stores)
            assert currents[0]['sessionId']!=currents[1]['sessionId']
            assert [s['platform'] for s in currents]==['web','admin']
            entry['resource_ids']=[uid]+[s['sessionId'] for s in currents]
            entry['steps']=['Same browser cookie jar, simultaneous User/Admin tabs of one synthetic identity',
                'Separate HttpOnly cookies and platform sessions','Identity/profile correct in both platforms','No JWT/password in local/session storage']
        stepcase(suite,web,'SESSION-COOKIE-PLATFORMS','AUTH-EXT-04','User/Admin tabs keep separate platform cookies and session IDs',cookies,'sessions')
        def web_logout(entry):
            remember_refresh(web)
            suite.go(web,'/account','app-account-page');p=web['page'];p.locator('.top-avatar').click();p.locator('.account-drawer__logout').click()
            p.locator('app-feedback-host .confirm-cancel').click();assert suite.api(web,'get','/auth/me').status==200
            p.locator('.account-drawer__logout').click()
            suite.response(web,'/auth/logout',lambda:p.locator('app-feedback-host .confirm-submit').click(),method='POST')
            suite.api(web,'get','/auth/me',expected=401);refresh(suite,web,401)
            suite.api(app,'get','/admin/me');freeze(app);refresh(suite,app)
            suite.go(app,'/account','app-account-page')
            web['page'].goto(web['origin']+'/account');web['page'].wait_for_url('**/login**')
            names={c['name'] for c in web['context'].cookies()}
            assert 'hutube_admin_refresh' in names and 'hutube_refresh' not in names
            entry['resource_ids']=[uid];entry['steps']=['User logout confirmation cancel preserves authentication','Confirm real User logout',
                'Old User JWT and refresh fail; protected User route denied','Admin token/cookie, refresh and reload remain valid in same cookie jar']
        stepcase(suite,web,'SESSION-USER-LOGOUT-ADMIN-SURVIVES','AUTH-EXT-04','User logout does not revoke same-browser Admin session',web_logout,'sessions')
        web=suite.actor('g1-web-restored','user','g1_priv',page=web['context'].new_page())
        def admin_logout(entry):
            remember_refresh(app)
            suite.go(app,'/account','app-account-page')
            suite.response(app,'/auth/logout',lambda:app['page'].locator('.section-heading > button.secondary').filter(has_text=re.compile('Đăng xuất|Logout|Sign out',re.I)).click(),method='POST')
            denied(suite,app,('/admin/me',))
            suite.api(web,'get','/auth/me');freeze(web);refresh(suite,web)
            suite.go(web,'/account','app-account-page')
            names={c['name'] for c in web['context'].cookies()}
            assert 'hutube_refresh' in names and 'hutube_admin_refresh' not in names
            entry['resource_ids']=[uid];entry['steps']=['Admin actual logout in shared cookie jar','Admin JWT/refresh/route denied',
                'User cookie, JWT/refresh and profile reload remain valid']
        stepcase(suite,web,'SESSION-ADMIN-LOGOUT-USER-SURVIVES','AUTH-EXT-04','Admin logout preserves User session',admin_logout,'sessions')
        def others(entry):
            other=suite.actor('g1-other-web','user','g1_priv');otheradmin=suite.actor('g1-other-admin','admin','g1_priv')
            try:
                remember_refresh(other);remember_refresh(otheradmin)
                suite.go(web,'/account','app-account-page');p=web['page'];p.locator('.settings-nav-list > button').nth(5).click()
                suite.response(web,'/auth/logout-others',lambda:p.locator('.sessions-actions button').first.click(),method='POST')
                denied(suite,other);denied(suite,otheradmin,('/admin/me',))
                suite.api(web,'get','/auth/me');freeze(web);refresh(suite,web)
                suite.go(web,'/account','app-account-page')
                sessions=suite.api(web,'get','/auth/sessions').json()['items'];assert len(sessions)==1 and sessions[0]['isCurrent']
                suite.api(foreign,'get','/auth/me')
                entry['resource_ids']=[uid,sessions[0]['sessionId']]
                entry['steps']=['User UI logs out other devices','Other User and Admin devices lose JWT/refresh/protected route',
                    'Controller remains authenticated and is the only active session','Foreign identity remains authenticated']
            finally:suite.release_actor(other);suite.release_actor(otheradmin)
        stepcase(suite,web,'SESSION-LOGOUT-OTHERS-CROSS-PLATFORM','U-ACCOUNT.03','Logout others preserves controller and revokes both platforms',others,'sessions')
        def current(entry):
            remember_refresh(web)
            current=next(s for s in suite.api(web,'get','/auth/sessions').json()['items'] if s['isCurrent'])
            suite.api(foreign,'delete','/auth/sessions/'+current['sessionId'],expected=404)
            suite.api(web,'get','/auth/me')
            suite.api(web,'delete','/auth/sessions/'+current['sessionId'])
            denied(suite,web)
            entry['resource_ids']=[uid,current['sessionId']]
            entry['steps']=['Foreign user cannot revoke current target session','Actual current-session DELETE',
                'Current JWT, refresh and protected route denied','UI intentionally has no revoke button on current row; current revoke endpoint tested']
        stepcase(suite,web,'SESSION-REVOKE-CURRENT','U-ACCOUNT.03','Current session revocation invalidates JWT and refresh',current,'sessions')
        web=suite.actor('g1-after-current-revoke','user','g1_priv')
        def all_devices(entry):
            other=suite.actor('g1-all-other','admin','g1_priv')
            try:
                remember_refresh(web);remember_refresh(other)
                suite.api(web,'post','/auth/logout-all',data={})
                denied(suite,web);denied(suite,other,('/admin/me',));suite.api(foreign,'get','/auth/me')
                entry['resource_ids']=[uid];entry['steps']=['Actual logout-all API','Controller and other platform lose JWT/refresh/routes','Foreign identity preserved']
            finally:suite.release_actor(other)
        stepcase(suite,web,'SESSION-LOGOUT-ALL','AUTH-EXT-04','Logout all revokes controller and Admin sessions',all_devices,'sessions')
        for platform in ['user','admin']:
            for mode in ['expires','inactive']:
                actor=suite.actor('g1-'+platform+'-'+mode,platform,'g1_priv')
                def expire(entry,actor=actor,mode=mode):
                    sid=next(s['sessionId'] for s in suite.api(actor,'get','/auth/sessions').json()['items'] if s['isCurrent'])
                    freeze(actor)
                    clause="expires_at=now()-interval '1 second'" if mode=='expires' else "last_active_at=now()-interval '90 days',issued_at=now()-interval '91 days'"
                    db.sql("UPDATE refresh_tokens SET "+clause+" WHERE refresh_token_id=:'sid'::uuid AND user_id=:'uid'::uuid;",{'sid':sid,'uid':uid})
                    denied(suite,actor,('/auth/me','/account/profile'))
                    entry['resource_ids']=[uid,sid];entry['fixture_preparation']='Only newly created session clock field adjusted in owned QC DB; no revocation result seeded'
                    entry['steps']=['Freeze this device token and stop polling','Prepare '+mode+' clock boundary on exact owned session','Backend rejects JWT and refresh','Browser protected route returns to login']
                stepcase(suite,actor,'SESSION-'+platform.upper()+'-'+mode.upper(),'AUTH-EXT-04',platform+' session '+mode+' boundary',expire,'sessions')
                suite.release_actor(actor)
        liveweb=suite.actor('g1-role-web','user','g1_priv');liveadmin=suite.actor('g1-role-admin','admin','g1_priv')
        def demote(entry):
            suite.api(liveweb,'get','/admin/topics');suite.api(liveadmin,'get','/admin/users')
            freeze(liveweb);freeze(liveadmin)
            suite.api(foreign,'put','/admin/users/'+foreign['identity']['userId']+'/role',data={'roleCode':'super_admin','reason':'QC denied elevation'},expected=403)
            suite.api(admin,'put','/admin/users/'+uid+'/role',data={'roleCode':'user','reason':'QC demote while both platforms logged in'})
            suite.api(liveweb,'get','/auth/me');suite.api(liveweb,'get','/admin/topics',expected=403)
            suite.api(liveweb,'get','/admin/users',expected=403);denied(suite,liveadmin,('/admin/me','/admin/users'))
            suite.go(liveweb,'/account','app-account-page');assert not suite.api(liveweb,'get','/auth/me').json()['isAdmin']
            entry['resource_ids']=[uid,role['roleId']]
            entry['steps']=['Both platforms initially use allowed custom permissions','Freeze tokens before demotion','Foreign user cannot self-elevate',
                'Stale User JWT loses Admin permissions immediately; basic profile survives','Stale Admin JWT/refresh/route denied after loss of admin access']
        stepcase(suite,liveweb,'ROLE-DEMOTION-LIVE-TWO-PLATFORMS','AUTH-EXT-04','Demotion immediately changes both platform sessions',demote,'rbac')
        suite.release_actor(liveweb);suite.release_actor(liveadmin)
    finally:
        suite.api(admin,'put','/admin/users/'+uid+'/role',data={'roleCode':'user','reason':'Cleanup isolated role fixture'})
        suite.api(admin,'delete','/admin/roles/'+role['roleId'],params={'reason':'Cleanup isolated security role'},expected=(204,404))
        for actor in list(suite.actors.values()):
            if actor['name'].startswith('g1-') and not actor.get('released'):suite.release_actor(actor)
    status_cases(suite,config,actors,db)

def status_cases(suite,config,actors,db):
    admin=actors['admin'];uid=identity(suite,config,'g1_status');key='g1_status';a=suite.actor('g1-status-web','user',key);b=suite.actor('g1-status-twin','user',key)
    def details():
        suite.go(admin,'/users','app-admin-users-page','/admin/users');p=admin['page'];p.locator('input[type=search]').fill(suite.credentials[key]['email'])
        row=p.locator('.user-row').filter(has_text=suite.credentials[key]['email']);expect(row).to_have_count(1);row.click();return p
    try:
        def locked(entry):
            remember_refresh(a);remember_refresh(b)
            p=details();p.locator('.detail-actions .link-action').nth(2).click();p.locator('[name=actionReason]').fill('QC status fixture only')
            p.locator('.action-modal').get_by_role('button',name=re.compile('Hủy|Huỷ|Cancel')).click()
            suite.api(a,'get','/auth/me');suite.api(b,'get','/auth/me')
            p.locator('.detail-actions .link-action').nth(2).click();p.locator('[name=actionReason]').fill('QC lock disposable identity')
            suite.response(admin,'/admin/users/'+uid+'/lock',lambda:p.locator('.action-modal button[type=submit]').click(),method='POST')
            denied(suite,a);denied(suite,b)
            suite.api(admin,'post','/admin/users/'+uid+'/unlock',data={'reason':'QC restore lock fixture','notify':False})
            suite.api(a,'get','/auth/me',expected=401)
            fresh=suite.actor('g1-status-unlocked','user',key);suite.api(fresh,'get','/auth/me');suite.release_actor(fresh)
            entry['resource_ids']=[uid];entry['steps']=['Cancel Admin lock preserves both active devices','Real Admin UI locks exact fresh account',
                'Both devices lose JWT/refresh/route','Unlock allows fresh login but old revoked token stays invalid']
        stepcase(suite,admin,'ACCOUNT-LOCK-CANCEL-TWO-DEVICES','AUTH-EXT-04','Lock/unlock enforces both active devices',locked,'security')
        for mode in ['suspended','deleted']:
            probe=suite.actor('g1-status-'+mode,'user',key)
            def blocked(entry,mode=mode,probe=probe):
                freeze(probe)
                clause="status='suspended'" if mode=='suspended' else "status='deleted',deleted_at=now()"
                db.sql("UPDATE users SET "+clause+",updated_at=now() WHERE user_id=:'uid'::uuid AND email=:'email'::citext;",{'uid':uid,'email':suite.credentials[key]['email']})
                denied(suite,probe)
                guest=suite.actor('g1-status-login-'+mode,'user','guest');guest['api_url']=config['api_url'];p=guest['page']
                suite.go(guest,'/login','app-auth-page');p.locator('#email').fill(suite.credentials[key]['email']);p.locator('#password').fill(suite.credentials[key]['password'])
                result=suite.response(guest,'/auth/login',lambda:p.locator('button[type=submit]').click(),method='POST',status=(401,403))
                assert 'user' not in result.json();expect(p.locator('[role=alert]')).to_be_visible();suite.release_actor(guest)
                entry['resource_ids']=[uid];entry['fixture_preparation']='Fresh synthetic user state set in isolated DB; no Admin suspend/delete UI/API exists. Only session/login enforcement is certified.'
                entry['steps']=['Valid existing login prepared','Set '+mode+' state only on owned new account','Old JWT/refresh/route denied','Real login UI rejects credential without returning profile']
            stepcase(suite,probe,'ACCOUNT-'+mode.upper()+'-SESSION-GATE','AUTH-EXT-04',mode+' account cannot continue existing session',blocked,'security')
            suite.release_actor(probe)
            if mode=='suspended':db.sql("UPDATE users SET status='active',updated_at=now() WHERE user_id=:'uid'::uuid;",{'uid':uid})
    finally:
        suite.release_actor(a);suite.release_actor(b)
