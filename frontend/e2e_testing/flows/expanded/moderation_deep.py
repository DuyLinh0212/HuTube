import re
from playwright.sync_api import expect
from flows.expanded.common import case,snapshot_module
from flows.expanded.media_deep import upload_fixture,submit_public,review_row
from flows.expanded.channels import png_bytes
from support.live_suite import PrerequisiteMissing

def run(suite,config,actors):
    snapshot_module(suite,__file__)
    from support.actor_readiness import ensure_actor_pages
    ensure_actor_pages(suite,actors,['owner','member','reviewer1','reviewer2'])
    owner,member,admin,r1,r2=(actors[k] for k in ['owner','member','admin','reviewer1','reviewer2'])
    video=upload_fixture(suite,owner,member,'DECISION');pending=submit_public(suite,owner,admin,video);mid=pending['moderationCaseId']
    def escalate(entry):
        row=review_row(suite,r1,video,0)
        suite.response(r1,'/admin/moderation/'+mid+'/claim',lambda:row.locator('.table-action.primary').click(),method='POST')
        row=review_row(suite,r1,video,1);row.locator('.table-action:not(.subtle)').first.click()
        r1['page'].locator('.decision-column input[type=text]').fill('QC escalation reason')
        response=suite.response(r1,'/admin/moderation/'+mid+'/resolve',lambda:r1['page'].locator('.decision-button.escalate').click(),method='POST')
        assert response.json()['status']=='escalated'
        suite.api(member,'get','/videos/'+video['videoId']+'/playback',expected=(403,409))
        review_row(suite,r1,video,3)
        entry['resource_ids']=[video['videoId'],mid];entry['steps']=['Reviewer UI claims fresh pending video','Escalate with explicit reason','Escalated queue contains same ID; ordinary Member cannot play pending content']
        entry['mail_manual']='NOT_EXECUTED; local notification evidence only'
    case(suite,r1,'MODERATION-ESCALATE','A-MODERATION.02','Escalation persists across User and Reviewer',escalate,'moderation')
    def reject(entry):
        row=review_row(suite,r1,video,3)
        suite.response(r1,'/admin/moderation/'+mid+'/claim',lambda:row.locator('.table-action.primary').click(),method='POST')
        row=review_row(suite,r1,video,1);row.locator('.table-action:not(.subtle)').first.click();p=r1['page']
        before=sum(e['method']=='POST' and e['path'].endswith('/resolve') for e in suite.report['http_statuses'])
        p.once('dialog',lambda d:d.accept());p.locator('.decision-button.reject').click()
        assert before==sum(e['method']=='POST' and e['path'].endswith('/resolve') for e in suite.report['http_statuses'])
        options=p.locator('.decision-column select option').evaluate_all('(options)=>options.map(o=>o.value).filter(Boolean)');assert options,'Reviewer policy read permission/fixture missing'
        p.locator('.decision-column select').select_option(options[0]);p.locator('.decision-column input[type=text]').fill('QC rejected fixture — có lý do và policy')
        suite.response(r1,'/admin/moderation/'+mid+'/resolve',lambda:p.locator('.decision-button.reject').click(),method='POST')
        current=suite.api(owner,'get','/videos/'+video['videoId']).json();assert current['moderationStatus']=='rejected' and current['status']=='blocked'
        suite.go(owner,'/studio/content?channelId='+video['channelId'],'app-studio-content-page')
        row=owner['page'].locator('.video-row').filter(has_text=video['title']);expect(row).to_contain_text('QC rejected fixture')
        suite.api(member,'get','/videos/'+video['videoId']+'/playback',expected=(403,409))
        suite.evidence(owner,entry,'creator-rejected-status')
        entry['resource_ids']=[video['videoId'],mid];entry['steps']=['Reject without policy triggers UI validation and no request','Select real policy + explicit reason → resolve','Owner API and Studio show rejected/blocked with reason','Member playback denied']
        entry['mail_manual']='NOT_EXECUTED; local Pickup/notification only'
    case(suite,r1,'MODERATION-REJECT-POLICY-REASON','A-MODERATION.02','Reject requires policy/reason and affects User',reject,'moderation')
    appeal={}
    def create_appeal(entry):
        request={'targetType':'video','targetId':video['videoId'],'reason':'QC owner appeals technical rejection','moderationCaseId':mid,'evidenceNote':'Owned test fixture'}
        suite.api(member,'post','/appeals',data=request,expected=403)
        appeal.update(suite.api(owner,'post','/appeals',data=request,expected=201).json())
        aid=appeal['appealId']
        result=suite.api(owner,'post','/appeals/'+aid+'/evidence',multipart={'file':{'name':'qc-evidence.png','mimeType':'image/png','buffer':png_bytes()}}).json();assert result['evidenceUrl']
        proof=suite.api(owner,'get','/appeals/'+aid+'/evidence');assert proof.body().startswith(b'\x89PNG')
        suite.api(member,'get','/appeals/'+aid+'/evidence',expected=(403,404))
        suite.api(r1,'post','/admin/appeals/'+aid+'/claim',data={},expected=(403,409))
        suite.go(owner,'/studio/content?channelId='+video['channelId'],'app-studio-content-page')
        entry['resource_ids']=[video['videoId'],mid,aid];entry['steps']=['Foreign Member cannot appeal owned video','Owner actual API creates pending appeal','Actual PNG evidence upload/read-back; foreign evidence denied','Original deciding reviewer cannot claim appeal (SoD)','Owner creator state remains inspectable']
    case(suite,owner,'APPEAL-OWNER-EVIDENCE-SOD','A-MODERATION.04','Owner evidence and reviewer separation of duties',create_appeal,'appeals')
    def resolve_appeal(entry):
        if not appeal:raise PrerequisiteMissing('No owner-created appeal checkpoint')
        aid=appeal['appealId'];p=r2['page'];suite.go(r2,'/moderation/appeals','app-admin-appeals-page','/admin/appeals')
        row=p.locator('tbody tr').filter(has_text=video['videoId']);expect(row).to_have_count(1)
        suite.response(r2,'/admin/appeals/'+aid+'/claim',lambda:row.get_by_role('button',name=re.compile('Nhận|Claim')).click(),method='POST',status=200)
        suite.response(r2,'/admin/appeals',lambda:p.locator('.status-tabs button').nth(1).click())
        row=p.locator('tbody tr').filter(has_text=video['videoId']);row.locator('.btn-resolve').click()
        dialog=p.locator('.modal-card');dialog.locator('select').select_option('approve');dialog.locator('textarea').fill('QC independent appeal approval')
        suite.response(r2,'/admin/appeals/'+aid+'/resolve',lambda:dialog.locator('.modal-footer .btn-primary').click(),method='POST')
        actual=suite.api(owner,'get','/videos/'+video['videoId']).json();assert actual['moderationStatus']=='approved'
        suite.api(member,'get','/videos/'+video['videoId']+'/playback')
        suite.api(r2,'post','/admin/appeals/'+aid+'/resolve',data={'decision':'approve','reviewNote':'QC replay'},expected=(400,409))
        entry['resource_ids']=[aid,video['videoId']];entry['steps']=['Reviewer2 UI claims exact appeal','Approve with explicit independent review note','Owner approved; Member playback restored','Processed appeal replay rejected']
        entry['mail_manual']='NOT_EXECUTED; local notification/Pickup only'
    case(suite,r2,'APPEAL-INDEPENDENT-APPROVE-REPLAY','A-MODERATION.04','Independent appeal approval restores video once',resolve_appeal,'appeals')
    conflict_video=upload_fixture(suite,owner,member,'REVIEW-OWNERSHIP');conflict=submit_public(suite,owner,admin,conflict_video);conflict_id=conflict['moderationCaseId']
    def resolve_ownership(entry):
        row=review_row(suite,r1,conflict_video,0);suite.response(r1,'/admin/moderation/'+conflict_id+'/claim',lambda:row.locator('.table-action.primary').click(),method='POST')
        before=suite.api(owner,'get','/videos/'+conflict_video['videoId']).json()
        response=suite.api(r2,'post','/admin/moderation/'+conflict_id+'/resolve',data={'decision':'approve','reason':'QC wrong reviewer must be denied'},expected=(200,403,409))
        entry['resource_ids']=[conflict_id,conflict_video['videoId']]
        assert response.status in (403,409),'Reviewer2 resolved Reviewer1 claimed case with HTTP '+str(response.status)
        after=suite.api(owner,'get','/videos/'+conflict_video['videoId']).json();assert after['moderationStatus']==before['moderationStatus']
        entry['steps']=['Reviewer1 UI claims fresh exact case','Separate Reviewer2 attempts decision','403/409 and no change to target moderation state']
    case(suite,r2,'REVIEWER-RESOLVE-OWNERSHIP','X-MODERATION.01','Another reviewer cannot decide the claimed case',resolve_ownership,'moderation')
    strike={};cid=video['channelId'];strike_reason='QC disposable manual strike '+suite.run_id
    def strike_effect(entry):
        suite.go(admin,'/moderation/strikes','app-admin-strikes-page','/admin/strikes')
        strike.update(suite.api(admin,'post','/admin/strikes',data={'channelId':cid,'severity':'high','reason':strike_reason,'internalNote':'Owned local fixture only'},expected=201).json())
        status=suite.api(owner,'get','/channels/'+cid+'/strikes').json();assert status['activeStrikesCount']>=1
        suite.api(owner,'post','/videos/upload-preflight',data={'channelId':cid,'fileSize':1024,'duration':10,'contentType':'video/mp4','sourceQuality':'360p'},expected=(400,403,409))
        suite.go(admin,'/moderation/strikes','app-admin-strikes-page','/admin/strikes');expect(admin['page'].locator('tbody tr').filter(has_text=strike_reason)).to_have_count(1)
        entry['resource_ids']=[cid,strike['strikeId']];entry['steps']=['Actual manual strike on owned test channel','Owner API active count/restriction updated','Upload preflight enforced; Admin row has same reason/ID']
    case(suite,admin,'STRIKE-EFFECTIVE-UPLOAD-RESTRICTION','A-MODERATION.05','Manual strike affects actual upload permission',strike_effect,'strikes')
    def revoke(entry):
        if not strike:raise PrerequisiteMissing('No manual strike fixture')
        suite.api(admin,'post','/admin/strikes/'+strike['strikeId']+'/revoke',data={'reason':'QC revoke fixture'})
        status=suite.api(owner,'get','/channels/'+cid+'/strikes').json();assert status['activeStrikesCount']==0
        suite.api(owner,'post','/videos/upload-preflight',data={'channelId':cid,'fileSize':1024,'duration':10,'contentType':'video/mp4','sourceQuality':'360p'})
        suite.go(admin,'/moderation/strikes','app-admin-strikes-page','/admin/strikes');admin['page'].locator('.status-tabs button').nth(2).click();expect(admin['page'].locator('tbody tr').filter(has_text=strike_reason)).to_have_count(1)
        entry['steps']=['Revoke owned manual strike with reason','Active count zero and upload preflight allowed again','Revoked tab retains original record/audit']
    case(suite,admin,'STRIKE-REVOKE-RESTORES-UPLOAD','A-MODERATION.05','Revocation restores upload without losing history',revoke,'strikes')
