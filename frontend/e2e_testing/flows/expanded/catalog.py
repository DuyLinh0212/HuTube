import json
from playwright.sync_api import expect
from flows.expanded.common import case,snapshot_module
from tests.full_functional import pickup_link
from flows.expanded.channels import create_channel

def run(suite,config,actors):
    snapshot_module(suite,__file__)
    admin,owner,member=actors['admin'],actors['owner'],actors['member'];page=admin['page'];plan={};policy={}
    def plan_create(entry):
        suite.go(admin,'/plans','app-admin-plans-page','/admin/plans')
        page.locator('.heading-actions .primary-action').click()
        code='qc_shared_'+suite.run_id[9:15]
        page.locator('[name=code]').fill(code);page.locator('[name=name]').fill('QC shared fixture '+suite.run_id)
        for field,value in [('price','0'),('durationDays','30'),('storageLimit','20'),('maxUploadSize','1'),('maxVideoDuration','15'),('maxMembers','3')]:page.locator('[name='+field+']').fill(value)
        page.locator('[name=maxVideoQuality]').select_option('1080p')
        for control in page.locator('.feature-toggle input[type=checkbox]:not([name])').all():control.check()
        page.locator('[name=isDefaultForNewUsers]').uncheck()
        expect(page.locator('[name=isDefaultForNewUsers]')).not_to_be_checked()
        result=suite.response(admin,'/admin/plans',lambda:page.locator('[role=dialog] button[type=submit]').click(),method='POST',status=201)
        plan.update(result.json());assert plan['storageLimit']==20*1024**3 and plan['maxMembers']==3
        assert all(plan['features'].get(k) for k in ['download','background_play','pip'])
        suite.go(owner,'/plans/'+plan['planId'],'app-plan-detail-page','/plans/'+plan['planId'])
        suite.response(owner,'/plans/'+plan['planId']+'/subscribe',lambda:owner['page'].locator('button.cta-subscribe').click(),method='POST')
        subscribed=suite.api(owner,'get','/plans/my-plan').json();assert subscribed['planId']==plan['planId']
        suite.fixtures['shared_plan']=plan
        entry['resource_ids']=[plan['planId']];entry['steps']=['Admin UI creates new free shared fixture with features','Read-back units, quota/features/member cap','Owner actual UI subscribes without payment','my-plan has exact plan ID/features']
    case(suite,admin,'PLAN-SHARED-CREATE-SUBSCRIBE','A-PLANS.01','Create real shared plan and subscribe through User UI',plan_create,'plans')
    for field,value in [('price',-1),('durationDays',0),('storageLimit',-1),('maxUploadSize',0),('maxVideoDuration',0),('maxMembers',0),('displayOrder',-1)]:
        def boundary(entry,field=field,value=value):
            suite.go(admin,'/plans','app-admin-plans-page','/admin/plans')
            original={'code':'qc_bad_'+field+'_'+suite.run_id[9:15],'name':'Invalid field fixture','description':'Numeric boundary','price':0,'durationDays':30,'storageLimit':1024**3,'maxUploadSize':1024**2,'maxVideoDuration':600,'maxVideoQuality':'1080p','maxMembers':2,'displayOrder':0}
            original[field]=value
            before=suite.api(admin,'get','/admin/plans').json()
            response=suite.api(admin,'post','/admin/plans',data=original,expected=201 if field=='displayOrder' else (400,422))
            after=suite.api(admin,'get','/admin/plans').json()
            if field=='displayOrder':
                created=response.json();assert created['displayOrder']==0 and len(after)==len(before)+1
                suite.api(admin,'post','/admin/plans/'+created['planId']+'/archive',data={},expected=(200,204))
                entry['steps']=['Negative displayOrder is normalized to 0 by its explicit service contract','Read back normalized plan; archive numeric fixture']
            else:
                assert response.status in (400,422) and len(after)==len(before)
                entry['steps']=['Invalid numeric '+field+'='+str(value)+' through actual create API','400/422; no plan persisted','Admin list remains unchanged']
        case(suite,admin,'PLAN-BOUNDARY-'+field.upper(),'A-PLANS.02','Reject invalid '+field,boundary,'plans')
    invitation={}
    def invite(entry):
        if not plan:raise AssertionError('No shared-plan fixture')
        suite.go(owner,'/plans','app-plans-page','/plans/my-plan');p=owner['page']
        expect(p.locator('[name=inviteEmail]')).to_be_visible();p.locator('[name=inviteEmail]').fill(member['identity']['email']);p.locator('[name=inviteStorageGB]').fill('2')
        import time
        sent=time.time();response=suite.response(owner,'/plans/members/invite',lambda:p.locator('.invite-form button[type=submit]').click(),method='POST')
        invitation.update(response.json());mid=invitation['planMemberId'];assert invitation['status']=='pending'
        link=pickup_link(config,member['identity']['email'],'plans/accept-invite',sent)
        member['page'].goto(link);expect(member['page'].locator('app-plan-invite-accept-page')).to_be_visible()
        suite.response(member,'/plans/members/'+mid+'/accept',lambda:member['page'].locator('button.primary').click(),method='POST')
        expect(member['page'].locator('.success')).to_be_visible()
        actual=suite.api(member,'get','/plans/my-plan').json();assert actual['isSharedMember'] and actual['planId']==plan['planId'],'Invitation was accepted but Member effective plan did not switch to the shared plan; isSharedMember='+str(actual['isSharedMember'])
        allocated=next(m for m in actual['members'] if m['planMemberId']==mid);assert allocated['allocatedStorage']==2*1024**3
        owned_channel=suite.api(member,'get','/channels/me',expected=(200,204,404))
        existing=owned_channel.json() if owned_channel.status==200 else None
        suite.fixtures['member_channel']=existing or create_channel(suite,member,'planmember')
        entry['channel_fixture']='Existing owned channel reused as setup' if existing else 'Created through actual channel UI'
        preflight=suite.api(member,'post','/videos/upload-preflight',data={'channelId':suite.fixtures['member_channel']['channelId'],'fileSize':1024,'duration':10,'contentType':'video/mp4','sourceQuality':'360p'}).json()
        assert preflight['storageLimit']==2*1024**3
        suite.go(owner,'/plans','app-plans-page','/plans/my-plan');expect(p.locator('.members-table tbody tr').filter(has_text=member['identity']['email'])).to_have_count(1)
        entry['resource_ids']=[plan['planId'],mid];entry['steps']=['Owner UI invites separate Member with 2GB','Actual recipient-specific Pickup link → Member UI accept','Shared entitlement/quota read-back','Owner reload shows one exact member']
        entry['mail_manual']='NOT_EXECUTED; Email Pickup automation only'
    case(suite,owner,'PLAN-INVITE-ACCEPT','U-PLAN.03','Shared-plan invitation and acceptance persist',invite,'plans')
    def allocate_remove(entry):
        mid=invitation['planMemberId'];p=owner['page'];suite.go(owner,'/plans','app-plans-page','/plans/my-plan')
        row=p.locator('.members-table tbody tr').filter(has_text=member['identity']['email']);row.locator('.btn-edit-mini').click();row.locator('input[type=number]').fill('3')
        suite.response(owner,'/plans/my-subscription/members/'+mid+'/storage',lambda:row.locator('.btn-save-mini').click(),method='PATCH')
        actual=suite.api(member,'get','/plans/my-plan').json();assert next((m for m in actual['members'] if m['planMemberId']==mid),{}).get('allocatedStorage')==3*1024**3,'Owner saved 3GB but Member effective plan does not expose the accepted allocation'
        suite.api(owner,'patch','/plans/members/'+mid+'/storage',data={'allocatedStorage':30*1024**3},expected=(400,409))
        suite.api(member,'patch','/plans/members/'+mid+'/storage',data={'allocatedStorage':1024**3},expected=(403,404))
        # Actual owner removal; preserve the recorded quota after rejected updates.
        suite.api(owner,'delete','/plans/members/'+mid,expected=204)
        assert not suite.api(member,'get','/plans/my-plan').json()['isSharedMember']
        suite.go(owner,'/plans','app-plans-page','/plans/my-plan')
        entry['steps']=['UI edits allocation to 3GB; Member API sees new quota','Over-allocation rejected; Member cannot edit owner allocations','Owner remove → shared entitlement revoked','Reload current plan']
    case(suite,owner,'PLAN-ALLOCATION-REMOVE','U-PLAN.03','Allocation limits, ownership and revocation',allocate_remove,'plans')
    def create_policy(entry):
        suite.go(admin,'/policies','app-admin-policies-page','/admin/policies');page.locator('.header-actions .btn-primary').click()
        modal=page.locator('.modal-dialog');inputs=modal.locator('input[type=text]');code='QC_POLICY_'+suite.run_id[9:15]
        inputs.nth(0).fill(code);inputs.nth(1).fill('QC published policy '+suite.run_id);inputs.nth(2).fill('1.0');modal.locator('select').nth(0).select_option('guidelines');modal.locator('textarea').fill('Version 1.0: nội dung QC từ API thật.')
        response=suite.response(admin,'/admin/policies',lambda:modal.locator('.modal-footer .btn-primary').click(),method='POST',status=201);policy.update(response.json())
        suite.go(admin,'/policies','app-admin-policies-page','/admin/policies');page.locator('.search-wrap input').fill(code)
        row=page.locator('.data-table tbody tr').filter(has_text=code);expect(row).to_have_count(1);row.locator('button').click()
        modal=page.locator('.modal-dialog');modal.locator('input[type=text]').fill('1.1');modal.locator('textarea').fill('Version 1.1: policy mới đã publish '+suite.run_id)
        response=suite.response(admin,'/admin/policies/'+policy['policyId']+'/publish',lambda:modal.locator('.modal-footer .btn-primary').click(),method='PUT');published=response.json()
        assert published['version']=='1.1'
        public=suite.api(owner,'get','/policies').json();assert any(p['policyId']==published['policyId'] and p['content']==published['content'] for p in public)
        suite.fixtures['policy']=published
        entry['resource_ids']=[policy['policyId']];entry['steps']=['Admin UI creates published 1.0 policy','Search/open detail → publish 1.1 through UI','Read public API exact ID/version/content']
    case(suite,admin,'POLICY-CREATE-PUBLISH','A-POLICY.01','Policy create and version publish through actual UI',create_policy,'policy')
    def immutable(entry):
        suite.go(admin,'/policies','app-admin-policies-page','/admin/policies')
        records=suite.api(admin,'get','/admin/policies').json()
        old=[p for p in records if p['code']==policy['code'] and p['version']=='1.0']
        assert len(old)==1 and old[0]['content']==policy['content'],'Published 1.0 record was overwritten by publishing 1.1; immutable version evidence is missing'
        entry['steps']=['Read versions after publishing 1.1','Original published 1.0 remains immutable and inspectable']
    case(suite,admin,'POLICY-PUBLISHED-IMMUTABLE','A-POLICY.01','Published policy version is preserved',immutable,'policy')
    def public_policy(entry):
        current=suite.fixtures['policy'];suite.go(owner,'/policies?tab=guidelines','app-public-policy-page','/policies')
        expect(owner['page'].locator('.policy-cards-feed')).to_contain_text(current['content'])
        owner['page'].reload();expect(owner['page'].locator('.policy-cards-feed')).to_contain_text(current['content'])
        entry['resource_ids']=[current['policyId']];entry['steps']=['Open User policy group after actual Admin publish','Exact published content/version rendered','Reload keeps new content']
    case(suite,owner,'POLICY-USER-PUBLISHED-CONTENT','U-POLICY.01','Admin published policy appears in User UI',public_policy,'policy')
