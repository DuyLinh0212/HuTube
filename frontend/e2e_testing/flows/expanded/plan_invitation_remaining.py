"""Expired/invalid shared-plan invitation with real mail link and unchanged quotas."""
import json,time
from urllib.parse import parse_qs,urlsplit
from playwright.sync_api import expect
from flows.expanded.common import case,snapshot_module
from flows.expanded.security_plan_common import identity
from support.actor_readiness import ensure_actor_pages
from support.local_db import LocalDb
from tests.full_functional import pickup_link

def run(suite,config,actors):
    snapshot_module(suite,__file__);ensure_actor_pages(suite,actors,['admin','member','target'])
    admin,member,foreign=actors['admin'],actors['member'],actors['target'];db=LocalDb(config)
    identity(suite,config,'plan_expiry_owner');owner=suite.actor('plan-expiry-owner','user','plan_expiry_owner');p=owner['page'];mp=member['page'];plan={};invitation={}
    baseline=suite.api(member,'get','/plans/my-plan').json()
    def unchanged():
        actual=suite.api(member,'get','/plans/my-plan').json()
        for field in ['planId','isSharedMember','storageLimit','usedStorage']:assert actual[field]==baseline[field],field+' changed on invalid invitation'
        rows=suite.api(owner,'get','/plans/my-plan').json()['members']
        row=next(v for v in rows if v['planMemberId']==invitation['planMemberId']);assert row['status']=='pending'
    try:
        def prepare(entry):
            plan.update(suite.api(admin,'post','/admin/plans',data={'code':'qc_invexp_'+suite.run_id[9:15],
                'name':'QC invite expiry '+suite.run_id,'description':'Disposable zero-price shared-plan fixture','price':0,'durationDays':30,
                'storageLimit':5*1024**3,'maxUploadSize':10*1024**2,'maxVideoDuration':60,'maxVideoQuality':'360p','maxDownloadQuality':'360p',
                'maxMembers':2,'features':'{}','isDefaultForNewUsers':False},expected=201).json())
            suite.go(owner,'/plans/'+plan['planId'],'app-plan-detail-page')
            suite.response(owner,'/plans/'+plan['planId']+'/subscribe',lambda:p.locator('button.cta-subscribe').click(),method='POST')
            assert suite.api(owner,'get','/plans/my-plan').json()['planId']==plan['planId']
            suite.go(owner,'/plans','app-plans-page','/plans/my-plan')
            p.locator('[name=inviteEmail]').fill(member['identity']['email']);p.locator('[name=inviteStorageGB]').fill('1');sent=time.time()
            invitation.update(suite.response(owner,'/plans/members/invite',lambda:p.locator('.invite-form button[type=submit]').click(),method='POST').json())
            iid=invitation['planMemberId'];link=pickup_link(config,member['identity']['email'],'plans/accept-invite',sent)
            query=parse_qs(urlsplit(link).query);assert query['memberId']==[iid]
            invitation['_link']=link;invitation['_token']=query['token'][0]
            assert invitation['status']=='pending';unchanged()
            entry['resource_ids']=[plan['planId'],iid,owner['identity']['userId']]
            entry['mail_manual']='NOT_EXECUTED; actual Email Pickup recipient/link verified only'
            entry['steps']=['Create independent synthetic owner and zero-price shared plan through real API','Actual Owner UI subscribes without payment','Actual UI invites existing independent Member with 1 GB allocation','Read recipient-specific real mail link; IDs agree','Pending invitation grants no entitlement or quota']
        if not case(suite,owner,'PLAN-INVITATION-EXPIRY-PREPARATION','U-PLAN.03','Pending shared-plan invitation grants nothing before acceptance',prepare,'plans'):return
        def invalid(entry):
            iid=invitation['planMemberId'];path='/plans/members/'+iid+'/accept'
            response=suite.api(member,'post',path,data={'token':'qc-invalid-token'},expected=400);assert response.json()['code']=='INVALID_TOKEN'
            response=suite.api(foreign,'post',path,data={'token':invitation['_token']},expected=403);assert response.json()['code']=='EMAIL_MISMATCH'
            unchanged()
            suite.go(member,'/plans/accept-invite','app-plan-invite-accept-page')
            expect(mp.locator('.invite-card .error')).to_be_visible();expect(mp.locator('.invite-card button')).to_have_count(0)
            entry['resource_ids']=[iid]
            entry['steps']=['Wrong actual token 400 INVALID_TOKEN','Valid token used by another identity 403 EMAIL_MISMATCH','Pending row and original member plan/quota unchanged','Incomplete invite route shows error and no accept button']
        case(suite,member,'PLAN-INVITATION-INVALID-TOKEN-IDENTITY-INCOMPLETE','U-PLAN.03','Invalid link or recipient cannot acquire shared entitlement',invalid,'plans')
        def expire(entry):
            iid=invitation['planMemberId'];mp.goto(invitation['_link']);expect(mp.locator('.invite-card button.primary')).to_be_visible()
            db.sql("UPDATE plan_invitation_tokens SET expires_at=now()+interval '2 seconds' WHERE plan_member_id=:'id'::uuid AND used_at IS NULL;",{'id':iid})
            mp.wait_for_timeout(3000)
            response=suite.response(member,'/plans/members/'+iid+'/accept',lambda:mp.locator('.invite-card button.primary').click(),method='POST',status=410)
            assert response.json()['code']=='INVITATION_EXPIRED';expect(mp.locator('.invite-card .error')).to_be_visible();expect(mp.locator('.invite-card .success')).to_have_count(0)
            unchanged()
            assert db.sql("SELECT count(*) FROM plan_invitation_tokens WHERE plan_member_id=:'id'::uuid AND used_at IS NOT NULL;",{'id':iid})=='0'
            entry['resource_ids']=[iid,plan['planId']]
            entry['mail_manual']='NOT_EXECUTED; actual Pickup link opened, no real mailbox certification'
            entry['steps']=['Load actual emailed invitation in recipient UI','Shorten only the exact owned token deadline; never seed a success/failure state','Wait backend clock and press real accept button','410 INVITATION_EXPIRED; UI error without success','Token stays unused, invitation pending, member plan/quota unchanged']
        case(suite,member,'PLAN-INVITATION-EXPIRED-NO-ENTITLEMENT','U-PLAN.03','Expired shared-plan token cannot activate entitlement',expire,'plans')
    finally:
        if invitation:suite.api(owner,'delete','/plans/members/'+invitation['planMemberId'],expected=204)
        if plan:suite.api(admin,'post','/admin/plans/'+plan['planId']+'/archive',data={},expected=204)
        suite.release_actor(owner)
