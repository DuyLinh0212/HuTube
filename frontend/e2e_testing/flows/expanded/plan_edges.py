from urllib.parse import urlsplit,parse_qs
from playwright.sync_api import expect
from flows.expanded.common import case,snapshot_module
from tests.full_functional import pickup_link

def run(suite,config,actors):
    snapshot_module(suite,__file__);owner,member,target=(actors[k] for k in ['owner','member','target']);current=suite.api(owner,'get','/plans/my-plan').json()
    selected=next((m for m in current['members'] if m['memberEmail']==member['identity']['email'] and m['status']=='accepted'),None)
    if selected is None:
        prepared=suite.api(owner,'post','/plans/members/invite',data={'email':member['identity']['email'],'allocatedStorage':1024**3}).json()
        link=pickup_link(config,member['identity']['email'],'plans/accept-invite');query=parse_qs(urlsplit(link).query);assert query['memberId']==[prepared['planMemberId']]
        suite.api(member,'post','/plans/members/'+prepared['planMemberId']+'/accept',data={'token':query['token'][0]})
        current=suite.api(owner,'get','/plans/my-plan').json();selected=next(m for m in current['members'] if m['planMemberId']==prepared['planMemberId'])
    if selected:
        mid=selected['planMemberId']
        def replay(entry):
            link=pickup_link(config,member['identity']['email'],'plans/accept-invite');query=parse_qs(urlsplit(link).query);assert query['memberId']==[mid]
            suite.api(member,'post','/plans/members/'+mid+'/accept',data={'token':query['token'][0]},expected=409)
            suite.go(owner,'/plans','app-plans-page','/plans/my-plan')
            entry['resource_ids']=[mid];entry['steps']=['Actual consumed invitation link from recipient Pickup','Same Member replays token → 409','Owner current plan still contains one accepted membership']
        case(suite,member,'PLAN-INVITATION-REPLAY','U-PLAN.03','Consumed shared invitation cannot be accepted twice',replay,'plans')
        def limits(entry):
            actual=suite.api(owner,'get','/plans/my-plan').json();assert actual['usedStorage']>0
            suite.api(owner,'patch','/plans/my-subscription/owner-storage',data={'allocatedStorage':1},expected=(400,409))
            suite.api(owner,'patch','/plans/members/'+mid+'/storage',data={'allocatedStorage':30*1024**3},expected=(400,409))
            suite.api(member,'patch','/plans/members/'+mid+'/storage',data={'allocatedStorage':1024**3},expected=(403,404))
            unchanged=suite.api(owner,'get','/plans/my-plan').json();row=next(m for m in unchanged['members'] if m['planMemberId']==mid);assert row['allocatedStorage']==selected['allocatedStorage']
            suite.go(owner,'/plans','app-plans-page','/plans/my-plan')
            entry['steps']=['Actual owner has uploaded bytes','Cannot reduce owner allocation below usedBytes','Cannot over-allocate shared member beyond plan capacity','Member cannot change own owner-controlled allocation','Rejected mutations preserve stored quota']
        case(suite,owner,'PLAN-ALLOCATION-USED-BYTES-OWNERSHIP','U-PLAN.03','Quota boundaries preserve actual allocations',limits,'plans')
        def remove(entry):
            suite.api(owner,'delete','/plans/members/'+mid,expected=204)
            after=suite.api(owner,'get','/plans/my-plan').json();row=next((m for m in after['members'] if m['planMemberId']==mid),None);assert row is None or row['status']=='revoked'
            suite.go(owner,'/plans','app-plans-page','/plans/my-plan');expect(owner['page'].locator('.members-table tbody tr').filter(has_text=member['identity']['email'])).to_have_count(0)
            entry['resource_ids']=[mid];entry['steps']=['Owner removes exact accepted membership','API excludes/revokes membership','Owner UI reload excludes member; shared entitlement bug is recorded separately']
        case(suite,owner,'PLAN-MEMBER-REMOVE-REVOKE','U-PLAN.03','Owner removal revokes persisted membership',remove,'plans')
    invitation={}
    def foreign(entry):
        invitation.update(suite.api(owner,'post','/plans/members/invite',data={'email':target['identity']['email'],'allocatedStorage':1024**3}).json());mid=invitation['planMemberId']
        link=pickup_link(config,target['identity']['email'],'plans/accept-invite');query=parse_qs(urlsplit(link).query);assert query['memberId']==[mid]
        suite.api(member,'post','/plans/members/'+mid+'/accept',data={'token':query['token'][0]},expected=403)
        actual=suite.api(owner,'get','/plans/my-plan').json();assert next(m for m in actual['members'] if m['planMemberId']==mid)['status']=='pending'
        suite.api(owner,'delete','/plans/members/'+mid,expected=204)
        suite.api(target,'post','/plans/members/'+mid+'/accept',data={'token':query['token'][0]},expected=409)
        suite.go(owner,'/plans','app-plans-page','/plans/my-plan');entry['resource_ids']=[mid]
        entry['steps']=['Owner real invite to distinct Target email','Foreign Member with actual token rejected by email ownership','Invitation stays pending','Owner revokes; correct Target cannot accept revoked token']
    try:case(suite,member,'PLAN-INVITE-FOREIGN-REVOKED','U-PLAN.03','Invitation rejects wrong actor and revocation replay',foreign,'plans')
    finally:
        if invitation:suite.api(owner,'delete','/plans/members/'+invitation['planMemberId'],expected=(204,404))
