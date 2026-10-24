"""Actual invitation decline/revoke/expiry with recipient and replay boundaries."""
import time
from urllib.parse import parse_qs,urlsplit
from playwright.sync_api import expect
from flows.expanded.common import case,snapshot_module
from flows.expanded.security_plan_common import identity
from support.actor_readiness import ensure_actor_pages
from support.local_db import LocalDb
from tests.full_functional import pickup_link

def run(suite,config,actors):
    snapshot_module(suite,__file__);ensure_actor_pages(suite,actors,['owner','member'])
    owner=actors['owner'];foreign=actors['member'];channel=suite.api(owner,'get','/channels/me').json();cid=channel['channelId']
    uid=identity(suite,config,'channel_edges');target=suite.actor('channel-edges','user','channel_edges');db=LocalDb(config);created=[]
    p=owner['page'];tp=target['page'];path='/channels/'+cid;route='/channel/'+channel['handle']+'/customize'
    def owner_ui():
        suite.go(owner,route,'app-channel-settings-page');p.locator('.settings-tabs-nav .tab-btn').nth(2).click()
        expect(p.locator('#inviteEmail')).to_be_visible()
    def recipient_ui():
        suite.go(target,'/channel-invitations','app-channel-invitations-page','/channels/invitations/me')
        return tp.locator('.invitation-card').filter(has_text=channel['name'])
    def state(iid):return db.sql("SELECT status FROM channel_invitations WHERE channel_invitation_id=:'id'::uuid;",{'id':iid})
    def no_membership():
        assert not any(c['channelId']==cid for c in suite.api(target,'get','/channels/accessible').json())
        assert not any(m['userId']==uid and m.get('status','active')=='active' for m in suite.api(owner,'get',path+'/members').json())
    def invite(entry):
        owner_ui();p.locator('#inviteEmail').fill(target['identity']['email']);p.locator('#inviteRole').select_option('editor');sent=time.time()
        invitation=suite.response(owner,path+'/members/invite',lambda:p.locator('.invite-form button[type=submit]').click(),method='POST',status=201).json()
        iid=invitation['channelInvitationId'];created.append(iid)
        link=pickup_link(config,target['identity']['email'],'channel-invitations',sent)
        assert parse_qs(urlsplit(link).query)['invitation']==[iid]
        assert state(iid)=='pending';entry['mail_manual']='NOT_EXECUTED; actual recipient/link verified in Email Pickup only'
        entry['resource_ids']=[cid,uid,iid];return iid
    try:
        def validation(entry):
            owner_ui();before={v['channelInvitationId'] for v in suite.api(owner,'get',path+'/invitations').json()}
            for email,status,code in [(owner['identity']['email'],400,'ALREADY_OWNER'),('qc.missing.'+suite.run_id+'@example.test',404,'USER_NOT_FOUND')]:
                p.locator('#inviteEmail').fill(email)
                response=suite.response(owner,path+'/members/invite',lambda:p.locator('.invite-form button[type=submit]').click(),method='POST',status=status)
                assert response.json()['code']==code;expect(p.locator('app-result-notice[tone=error]')).to_be_visible();expect(p.locator('.invite-form button[type=submit]')).to_be_enabled()
            response=suite.api(owner,'post',path+'/members/invite',data={'email':target['identity']['email'],'roleCode':'owner'},expected=400)
            assert response.json()['code']=='INVALID_ROLE'
            assert before=={v['channelInvitationId'] for v in suite.api(owner,'get',path+'/invitations').json()}
            entry['resource_ids']=[cid];entry['steps']=['Owner actual invite form rejects self and nonexistent recipient with exact errors','Busy state ends and errors visible','API owner-role invitation rejected','Pending invitation ID set unchanged']
        case(suite,owner,'CHANNEL-INVITE-SELF-MISSING-ROLE-VALIDATION','U-CHANNEL.04','Invalid invitations create no pending rows',validation,'channel')
        def decline(entry):
            iid=invite(entry)
            duplicate=suite.api(owner,'post',path+'/members/invite',data={'email':target['identity']['email'],'roleCode':'editor'},expected=409)
            assert duplicate.json()['code']=='INVITATION_ALREADY_SENT'
            suite.api(foreign,'post','/channels/invitations/'+iid+'/accept',data={},expected=403)
            card=recipient_ui();expect(card).to_have_count(1)
            suite.response(target,'/channels/invitations/'+iid+'/decline',lambda:card.locator('.button--secondary').click(),method='POST',status=204)
            expect(card).to_have_count(0);assert state(iid)=='declined';no_membership()
            suite.api(target,'post','/channels/invitations/'+iid+'/accept',data={},expected=409)
            suite.api(target,'post','/channels/invitations/'+iid+'/decline',data={},expected=409)
            tp.reload();expect(tp.locator('.invitation-card').filter(has_text=channel['name'])).to_have_count(0)
            entry['steps']=['Owner UI creates exact recipient invitation and real Pickup mail link','Duplicate pending invite 409; foreign accept 403','Recipient actual Decline button persists declined','No channel membership granted; accept/decline replay denied','Reload removes invitation without stale card']
        case(suite,target,'CHANNEL-INVITATION-DECLINE-REPLAY-ISOLATION','U-CHANNEL.04','Declining invitation cannot grant or replay membership',decline,'channel')
        def revoke(entry):
            iid=invite(entry);owner_ui();row=p.locator('.invitation-row').filter(has_text=target['identity']['email']);expect(row).to_have_count(1)
            suite.response(owner,path+'/invitations/'+iid,lambda:row.locator('.btn-link-danger').click(),method='DELETE',status=204)
            expect(row).to_have_count(0);assert state(iid)=='revoked'
            denied=suite.api(target,'post','/channels/invitations/'+iid+'/accept',data={},expected=400);assert denied.json()['code']=='INVITATION_REVOKED'
            suite.api(owner,'delete',path+'/invitations/'+iid,expected=409);no_membership()
            card=recipient_ui();expect(card).to_have_count(0)
            entry['steps']=['Owner creates a fresh independent invitation','Actual owner Withdraw button removes exact pending row','Persisted revoked; recipient accept returns INVITATION_REVOKED','Repeated withdrawal denied; no membership; recipient reload shows no pending card']
        case(suite,owner,'CHANNEL-INVITATION-OWNER-REVOKE-REPLAY','U-CHANNEL.04','Withdrawn invitation cannot be accepted',revoke,'channel')
        def expire(entry):
            iid=invite(entry);card=recipient_ui();expect(card).to_have_count(1)
            db.sql("UPDATE channel_invitations SET expires_at=now()+interval '2 seconds' WHERE channel_invitation_id=:'id'::uuid AND invited_user_id=:'uid'::uuid AND status='pending';",{'id':iid,'uid':uid})
            tp.wait_for_timeout(3000)
            response=suite.response(target,'/channels/invitations/'+iid+'/accept',lambda:card.locator('.button--primary').click(),method='POST',status=410)
            assert response.json()['code']=='INVITATION_EXPIRED';expect(tp.locator('[role=alert]')).to_be_visible()
            assert state(iid)=='expired';no_membership()
            suite.api(target,'post','/channels/invitations/'+iid+'/decline',data={},expected=410)
            card=recipient_ui();expect(card).to_have_count(0)
            entry['steps']=['Pending real invitation loaded in recipient UI','Shorten only exact owned invitation deadline, never response/status/membership','Wait actual backend clock; stale UI accept receives INVITATION_EXPIRED 410','Actual backend persists expired; no membership and decline also denied','Reload removes expired invitation']
        case(suite,target,'CHANNEL-INVITATION-EXPIRY-STALE-UI','U-CHANNEL.04','Expired invitation is rejected even from a previously loaded card',expire,'channel')
    finally:
        for iid in created:
            if state(iid)=='pending':suite.api(owner,'delete',path+'/invitations/'+iid,expected=204)
        suite.release_actor(target)
