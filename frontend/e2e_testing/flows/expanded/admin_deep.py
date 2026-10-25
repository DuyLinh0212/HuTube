import uuid
from playwright.sync_api import expect
from flows.expanded.common import case,snapshot_module
from flows.expanded.channels import create_channel
from support.live_suite import PrerequisiteMissing
from support.local_db import LocalDb
from tests.full_functional import register

def run(suite,config,actors):
    snapshot_module(suite,__file__)
    admin,target,member,owner=actors['admin'],actors['target'],actors['member'],actors['owner'];page=admin['page'];uid=target['identity']['userId']
    # The target has been idle since channel deletion. Prepare a live session
    # before testing lock/revoke, and close the completed earlier tab.
    suite.release_actor(target)
    target=actors['target']=suite.actor('target-admin-mutations','user','target')
    def target_detail():
        suite.go(admin,'/users','app-admin-users-page','/admin/users')
        search=page.locator('input[type=search]');search.fill(target['identity']['email'])
        row=page.locator('.user-row').filter(has_text=target['identity']['email']);expect(row).to_have_count(1)
        # Filtering auto-selects the only row and may already have loaded detail.
        row.click()
        expect(page.locator('.detail-actions')).to_be_visible()
        assert suite.api(admin,'get','/admin/users/'+uid).json()['userId']==uid
    def lock_unlock(entry):
        try:
            assert suite.api(target,'get','/auth/me').json()['userId']==uid
            target_detail();page.locator('.detail-actions .link-action').nth(2).click()
            expect(page.locator('.action-modal button[type=submit]')).to_be_disabled()
            page.locator('[name=actionReason]').fill('QC lock only disposable target')
            suite.response(admin,'/admin/users/'+uid+'/lock',lambda:page.locator('.action-modal button[type=submit]').click(),method='POST')
            locked=suite.api(admin,'get','/admin/users/'+uid).json();assert locked['status'] in ('banned','suspended')
            suite.api(target,'get','/auth/me',expected=(401,403))
            target['page'].reload();target['page'].wait_for_url('**/login**')
            target_detail();page.locator('.detail-actions .link-action').nth(2).click();page.locator('[name=actionReason]').fill('QC restore disposable target')
            suite.response(admin,'/admin/users/'+uid+'/unlock',lambda:page.locator('.action-modal button[type=submit]').click(),method='POST')
            restored=suite.api(admin,'get','/admin/users/'+uid).json();assert restored['status']=='active'
            suite.release_actor(target);actors['target']=suite.actor('target-unlocked','user','target')
            entry['resource_ids']=[uid];entry['steps']=['Fresh live fixture session returns exact ID','Actual Admin UI requires lock reason','Lock fixture target → old User JWT/reload denied','UI unlock → active','Fresh login returns same ID; audit record retained']
            entry['mail_manual']='NOT_EXECUTED; local notification/Pickup only'
        finally:
            state=suite.api(admin,'get','/admin/users/'+uid).json()
            if state['status']!='active':
                suite.api(admin,'post','/admin/users/'+uid+'/unlock',data={'reason':'QC cleanup after unfinished lock assertion'})
                suite.report['cleanup'].append({'resource':'disposable locked target','id':uid,'status':'unlocked-after-incomplete-test'})
    case(suite,admin,'USER-LOCK-UNLOCK-SESSION','A-USERS.02','Lock/unlock revokes active target session',lock_unlock,'users')
    custom={}
    def role_assignment(entry):
        nonlocal target
        target=actors['target'];code='qc_permission_'+suite.run_id[9:15]
        custom.update(suite.api(admin,'post','/admin/roles',data={'code':code,'name':'QC assigned role','description':'Disposable role','permissionCodes':['taxonomy.manage'],'reason':'QC role fixture'},expected=201).json())
        target_detail();page.locator('.detail-actions .link-action').nth(1).click();page.locator('[name=actionRole]').select_option(code);page.locator('[name=actionReason]').fill('QC assign custom role')
        suite.response(admin,'/admin/users/'+uid+'/role',lambda:page.locator('.action-modal button[type=submit]').click(),method='PUT')
        actual=suite.api(admin,'get','/admin/users/'+uid).json();assert actual['roleCode']==code and 'taxonomy.manage' in actual['permissions']
        current_identity=suite.api(target,'get','/auth/me',expected=(200,401,403))
        if current_identity.status==200:assert current_identity.json()['userId']==uid
        fresh=suite.actor('target-with-custom-role','user','target')
        suite.api(fresh,'get','/admin/topics')
        suite.api(fresh,'get','/admin/roles',expected=403)
        suite.api(member,'put','/admin/users/'+member['identity']['userId']+'/role',data={'roleCode':'super_admin','reason':'QC self elevation must fail'},expected=403)
        suite.api(admin,'delete','/admin/roles/'+custom['roleId'],params={'reason':'QC delete assigned custom role'},expected=204)
        removed=suite.api(admin,'get','/admin/users/'+uid).json()
        assert removed['roleCode'] is None and removed['permissions']==[]
        suite.api(fresh,'get','/admin/topics',expected=(401,403))
        suite.api(admin,'post','/admin/roles',data={'code':code,'name':'Duplicate','permissionCodes':[],'reason':'QC duplicate'},expected=409)
        suite.go(admin,'/roles','app-admin-rbac-page','/admin/roles');page.locator('.role-browser input[type=search]').fill(code);expect(page.locator('.role-card')).to_have_count(0)
        old_headers=dict(fresh['headers']);fresh['page'].goto('about:blank')
        suite.api(admin,'put','/admin/users/'+uid+'/role',data={'roleCode':'user','reason':'QC restore role fixture'})
        fresh['headers']=old_headers
        suite.api(fresh,'get','/admin/topics',expected=(401,403))
        suite.release_actor(fresh);suite.release_actor(target);actors['target']=suite.actor('target-role-restored','user','target')
        entry['resource_ids']=[uid,custom['roleId']];entry['steps']=['Create one custom role via real API','Admin UI assigns it; current identity reflects updated role','Re-login: taxonomy allowed, RBAC denied','Ordinary Member cannot self-elevate','Delete assigned role: member has no role/permissions and old session loses access','Deleted code cannot be recreated; deleted role absent from picker','Super Admin can assign User role again']
    case(suite,admin,'RBAC-ASSIGN-RELOGIN-CONSTRAINTS','A-RBAC.01','Assigned permissions take effect after re-login',role_assignment,'rbac')
    def system_role(entry):
        roles=suite.api(admin,'get','/admin/roles').json();system=next(r for r in roles if r['code']=='super_admin')
        suite.api(admin,'delete','/admin/roles/'+system['roleId'],params={'reason':'QC system role constraint'},expected=(400,403,409))
        after=suite.api(admin,'get','/admin/roles').json();assert any(r['roleId']==system['roleId'] for r in after)
        suite.go(admin,'/roles','app-admin-rbac-page','/admin/roles');page.locator('.role-browser input[type=search]').fill('super_admin');expect(page.locator('.role-card')).to_have_count(1)
        entry['steps']=['Actual delete of system role rejected','Read-back shows original system ID still present','UI role browser still contains protected system role']
    case(suite,admin,'RBAC-SYSTEM-ROLE','A-RBAC.02','System role cannot be deleted',system_role,'rbac')
    if config.get('only_rbac'):return
    def dataset(entry):
        # Fixture preparation uses real registration endpoints. These pending
        # accounts are not counted as verified actors or registration test passes.
        guest=suite.actor('pagination-dataset','user','guest');guest['api_url']=config['api_url']
        existing_total=suite.api(admin,'get','/admin/users',params={'page':1,'pageSize':1}).json()['total']
        for i in range(max(0,55-existing_total)):
            name='qc_page_'+suite.run_id[9:15]+'_'+str(i)
            suite.api(guest,'post','/auth/register',data={'username':name,'email':name+'@example.test','displayName':'QC pagination '+str(i),'password':'QCPaginationFixture2026!'},expected=201)
        data=suite.go(admin,'/users','app-admin-users-page','/admin/users');assert data['total']>50
        ids={v['userId'] for v in data['items']}
        # Request subsequent pages and compare the visible exact API rows.
        fifty=suite.api(admin,'get','/admin/users',params={'page':1,'pageSize':50}).json();assert len(fifty['items'])==50
        second=suite.response(admin,'/admin/users',lambda:page.locator('.pagination button').nth(1).click(),params={'page':2}).json()
        rendered=page.locator('.user-row').all_inner_texts();assert len(rendered)==len(second['items'])
        assert not ids.intersection(v['userId'] for v in second['items'])
        entry['steps']=['Owned real synthetic-account dataset populated to at least 55 rows','Admin actual total exceeds 50','API pageSize 50 returns fifty exact IDs','UI next page has disjoint IDs and correct rendered row count']
    case(suite,admin,'USERS-DATASET-PAGINATION','A-USERS.01','Real dataset beyond fifty users',dataset,'users')
    channel_actor=actors['target']
    existing=suite.api(channel_actor,'get','/channels/me',expected=(200,404))
    extra_channel_actor=None
    if existing.status==200:
        # A resumed target may already own the prior secondary fixture. Create
        # a distinct disposable owner rather than deleting/relabeling its channel.
        key='admin_secondary_owner'
        suite.credentials[key]={'email':'qc.admin.secondary.'+suite.run_id.lower()+'@example.test',
            'username':'qc_as_'+suite.run_id.lower().replace('.','_'),'password':'QCSecondaryOwner2026!'}
        register(suite,config,key,LocalDb(config))
        extra_channel_actor=channel_actor=suite.actor('admin-secondary-owner','user',key)
    secondary=create_channel(suite,channel_actor,'adminsecondary');sid=secondary['channelId'];suite.fixtures['admin_secondary']=secondary
    for index,(state,endpoint) in enumerate([('suspended','suspend'),('active','unban'),('banned','ban'),('active','unban')]):
        def channel_status(entry,state=state,endpoint=endpoint):
            target=channel_actor;suite.go(admin,'/channels','app-admin-channels-page','/admin/channels')
            response=suite.api(admin,'post','/admin/channels/'+sid+'/'+endpoint,data={'reason':'QC '+state+' fixture only'},expected=204)
            current=suite.api(target,'get','/channels/me').json();assert current['status']==state
            suite.go(target,'/channel/'+secondary['handle']+'/customize','app-channel-settings-page')
            if state!='active':
                expect(target['page'].locator('.channel-suspended-banner')).to_be_visible()
                suite.api(target,'post','/videos/upload-preflight',data={'channelId':sid,'fileSize':1024,'duration':10,'contentType':'video/mp4','sourceQuality':'360p'},expected=(400,403,404,409))
            assert suite.api(owner,'get','/channels/me').json()['status']=='active'
            entry['resource_ids']=[sid];entry['steps']=['Admin real status mutation '+state,'Target UI/API refresh reflects restriction','Restricted upload preflight denied; main owner unchanged']
        case(suite,admin,'ADMIN-CHANNEL-'+str(index+1)+'-'+endpoint.upper()+'-'+state.upper(),'A-CHANNELS.02','Channel '+state+' enforcement',channel_status,'channels')
    def missing(entry):
        random_id=str(uuid.uuid4());suite.api(admin,'get','/admin/users/'+random_id,expected=404)
        suite.api(member,'get','/admin/users/'+uid,expected=403)
        target_detail();entry['steps']=['Missing user ID returns 404','Member cannot read Admin target details','Actual target detail opens after errors; no stale different ID']
    case(suite,admin,'ADMIN-MISSING-AND-DENIED-DETAIL','A-USERS.01','Missing and forbidden detail boundaries',missing,'users')
    if extra_channel_actor:suite.release_actor(extra_channel_actor)
