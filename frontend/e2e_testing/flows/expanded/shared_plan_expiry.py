"""Fresh owner/member sharing, real upload, expiry and worker quota restoration."""
import time
from playwright.sync_api import expect
from support.local_db import LocalDb
from flows.expanded.common import case,snapshot_module
from flows.expanded.security_plan_common import identity
from flows.expanded.channels import create_channel
from flows.expanded.plan_lifecycle import pause_worker
from flows.expanded.media_deep import upload_fixture
from tests.full_functional import pickup_link

def run(suite,config,actors):
    snapshot_module(suite,__file__);db=LocalDb(config);admin=actors['admin']
    oid=identity(suite,config,'shared_exp_owner');mid=identity(suite,config,'shared_exp_member')
    owner=suite.actor('shared-exp-owner','user','shared_exp_owner');member=suite.actor('shared-exp-member','user','shared_exp_member')
    oc=create_channel(suite,owner,'sharedexpowner');mc=create_channel(suite,member,'sharedexpmember')
    original=suite.fixtures['channel'];video=suite.fixtures['video']['videoId'];plan={};state={}
    initial=suite.api(member,'get','/plans/my-plan').json();default_id=initial['planId']
    def current():return suite.api(member,'get','/plans/my-plan').json()
    try:
        def accept(entry):
            plan.update(suite.api(admin,'post','/admin/plans',data={'code':'qc_shared_exp_'+suite.run_id[9:15],
                'name':'QC Shared Expiry '+suite.run_id,'price':0,'durationDays':30,'storageLimit':20*1024**3,
                'maxUploadSize':5*1024**2,'maxVideoDuration':60,'maxVideoQuality':'1080p','maxDownloadQuality':'1080p',
                'maxMembers':3,'features':'{"pip":true,"background_play":true,"download":true}',
                'isDefaultForNewUsers':False},expected=201).json())
            suite.api(owner,'post','/plans/'+plan['planId']+'/subscribe',data={})
            state['history']=suite.api(owner,'get','/plans/my-plan').json()['subscription']['planHistoryId']
            invited=suite.api(owner,'post','/plans/members/invite',data={'email':suite.credentials['shared_exp_member']['email'],'allocatedStorage':1024**3}).json()
            link=pickup_link(config,suite.credentials['shared_exp_member']['email'],'plans/accept-invite')
            p=member['page'];p.goto(link);expect(p.locator('app-plan-invite-accept-page')).to_be_visible()
            suite.response(member,'/plans/members/'+invited['planMemberId']+'/accept',lambda:p.locator('button.primary').click(),method='POST')
            actual=current();assert actual['isSharedMember'] and actual['planId']==plan['planId']
            suite.api(member,'get','/videos/'+video+'/download-options')
            suite.go(member,'/plans','app-plans-page','/plans/my-plan')
            entry['resource_ids']=[oid,mid,invited['planMemberId'],state['history']]
            entry['steps']=['Fresh owner and Member with their own channels','Real free high plan subscription; actual recipient invitation',
                'Member UI accepts genuine Pickup link','Shared features and allocated quota effective']
        if not case(suite,member,'SHARED-EXPIRY-ACCEPT-BASELINE','U-PLAN.04','Shared entitlement baseline before owner expiry',accept,'plans'):return
        suite.fixtures['channel']=mc
        try:uploaded=upload_fixture(suite,member,owner,'SHARED-EXPIRY')
        finally:suite.fixtures['channel']=original
        used=current()['usedStorage'];assert used>0
        with pause_worker(config):
            db.sql("UPDATE plan_histories SET ended_at=now()+interval '3 seconds' WHERE plan_history_id=:'hid'::uuid AND user_id=:'uid'::uuid;",{'hid':state['history'],'uid':oid})
            member['page'].wait_for_timeout(4500)
            def immediate(entry):
                actual=current();assert not actual['isSharedMember'] and actual['planId']==default_id
                assert not any(actual['features'].get(k) for k in ['download','pip','background_play'])
                assert actual['usedStorage']==used
                suite.api(member,'get','/videos/'+video+'/download-options',expected=403)
                suite.go(member,'/watch/'+video,'app-watch-page');expect(member['page'].locator('.player-pip-button')).to_be_disabled()
                entry['resource_ids']=[mid,state['history'],uploaded['videoId']]
                entry['fixture_preparation']='Only fresh owner history ended_at clock changed; real expiry awaited with worker paused'
                entry['steps']=['Owner shared history genuinely expires','Member immediately loses shared features before worker',
                    'Default read-back and uploaded bytes preserved','Download API 403 and Watch PiP disabled']
            case(suite,member,'SHARED-EXPIRY-IMMEDIATE-REVOKE','U-PLAN.04','Member loses expired owner rights before worker',immediate,'plans')
        def restored(entry):
            deadline=time.monotonic()+100
            while time.monotonic()<deadline:
                status=db.sql("SELECT status FROM plan_histories WHERE plan_history_id=:'hid'::uuid;",{'hid':state['history']})
                if status=='expired':break
                member['page'].wait_for_timeout(2000)
            else:raise AssertionError('Real expiry worker did not process shared owner history')
            actual=current();assert actual['planId']==default_id and actual['usedStorage']==used
            preflight=suite.api(member,'post','/videos/upload-preflight',data={'channelId':mc['channelId'],'fileSize':1024,
                'duration':10,'contentType':'video/mp4','sourceQuality':'360p'}).json()
            entry['observed_quota']={'api_storage_limit':preflight['storageLimit'],'plan_storage_limit':actual['storageLimit']}
            assert preflight['storageLimit']==actual['storageLimit'],'Member quota remains allocated shared quota after owner expiry worker'
            suite.api(member,'get','/videos/'+uploaded['videoId'])
            suite.go(member,'/plans','app-plans-page','/plans/my-plan')
            entry['resource_ids']=[mid,state['history'],uploaded['videoId']]
            entry['steps']=['Release worker lock; wait real periodic processing','Member plan restored without deleting actual upload',
                'Upload-preflight storage quota equals effective personal/default plan','Reload Member plans retains restored state']
        case(suite,member,'SHARED-EXPIRY-WORKER-QUOTA','U-PLAN.04','Worker restores shared Member quota consistently',restored,'plans')
    finally:
        suite.fixtures['channel']=original
        if plan:suite.api(admin,'post','/admin/plans/'+plan['planId']+'/archive',data={},expected=(200,204))
        suite.release_actor(owner);suite.release_actor(member)
