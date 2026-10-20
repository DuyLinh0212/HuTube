"""Actual Member report dialog -> independent reviewer classification/decision."""
from playwright.sync_api import expect
from flows.expanded.common import case,snapshot_module
from support.live_suite import PrerequisiteMissing

def run(suite,config,actors):
    snapshot_module(suite,__file__)
    from support.actor_readiness import ensure_actor_pages
    ensure_actor_pages(suite,actors,['owner','member','reviewer1','reviewer2'])
    member,r1,r2,owner=(actors[k] for k in ['member','reviewer1','reviewer2','owner'])
    suite.go(owner,'/account','app-account-page','/account/profile')
    actual=suite.api(owner,'get','/videos/manage',params={'channelId':suite.fixtures['channel']['channelId'],'page':1,'pageSize':100}).json()['items']
    prior_targets=set();report_page=1
    while True:
        prior=suite.api(actors['admin'],'get','/admin/reports/cases',params={'page':report_page,'pageSize':100}).json()
        prior_targets.update(c['targetId'] for c in prior['items'] if c['targetType']=='video')
        if report_page*prior['pageSize']>=prior['total']:break
        report_page+=1
    candidates=[v for v in actual if v['videoId'] not in prior_targets and 'music QC dataset' in v['title'] and v['visibility']=='public' and v['moderationStatus']=='approved' and v['status']=='published']
    if len(candidates)<7:raise PrerequisiteMissing('Seven independent approved report targets required')
    for decision,video in zip(['dismiss','warn','age_restrict','recommendation_restricted','hide','remove','escalate'],candidates):
        checkpoint={};vid=video['videoId'];title=video['title'];base='/admin/reports/cases'
        def report(entry,vid=vid,title=title):
            suite.go(member,'/watch/'+vid,'app-watch-page');p=member['page']
            p.get_by_role('button',name=__import__('re').compile('Báo.*vi phạm|Report violation',__import__('re').I)).click()
            modal=p.locator('.report-modal');expect(modal.locator('.btn-next')).to_be_disabled();modal.locator('.option-row').first.click();modal.locator('.btn-next').click()
            modal.locator('.btn-back').click();expect(modal.locator('.option-row.is-selected')).to_have_count(1);modal.locator('.btn-next').click()
            modal.locator('textarea').fill('QC real Member report '+decision+' '+suite.run_id)
            created=suite.response(member,'/reports',lambda:modal.locator('.btn-submit').click(),method='POST',status=(200,201)).json()
            data=suite.api(r1,'get',base,params={'page':1,'pageSize':100}).json();items=data if isinstance(data,list) else data['items']
            checkpoint.update(next(c for c in items if c['targetId']==vid and c['targetType']=='video'))
            assert checkpoint['reportCount']>=1
            entry['resource_ids']=[vid,checkpoint['caseId']];entry['steps']=['Member opens real Watch report modal','Reason required; next/back retains chosen option','Submit actual report with distinct target ID','Reviewer API sees same target grouped in pending case']
        if not case(suite,member,'REPORT-CREATE-'+decision.upper(),'U-WATCH.05','Member reports target for '+decision,report,'reports'):continue
        def resolve(entry,vid=vid,decision=decision,title=title):
            case_id=checkpoint['caseId'];path=base+'/'+case_id;p=r1['page']
            guest=suite.actor('report-eligibility-'+decision,'user','guest');guest['api_url']=config['api_url']
            def feed_ids():
                ids=[];page=1
                while True:
                    result=suite.api(guest,'get','/feed/home',params={'sort':'newest','page':page,'pageSize':100}).json();ids.extend(v['videoId'] for v in result['items'])
                    if page*result['pageSize']>=result['total']:return ids
                    page+=1
            if decision=='recommendation_restricted':assert vid in feed_ids(),'Recommendation target must be eligible before the decision'
            suite.go(r1,'/moderation/reports','app-admin-reports-page',base)
            p.locator('input.report-search').fill(title)
            row=p.locator('tbody tr').filter(has_text=title);expect(row).to_have_count(1)
            suite.response(r1,path+'/claim',lambda:row.locator('.btn-claim').click(),method='POST',status=200)
            suite.api(r2,'post',path+'/claim',data={},expected=409)
            suite.api(r2,'post',path+'/resolve',data={'decision':decision,'reason':'Foreign reviewer','internalNote':None,'policyCode':None},expected=(403,409))
            suite.api(r1,'post',path+'/resolve',data={'decision':decision,'reason':'Before classification','internalNote':None,'policyCode':None},expected=409)
            p.locator('.status-tabs button').nth(1).click();row=p.locator('tbody tr').filter(has_text=title);row.locator('.btn-resolve').click()
            detail=suite.api(r1,'get',path).json();ids=[r['reportId'] for r in detail['reports']]
            suite.api(r1,'post',path+'/dispositions',data={'reportIds':ids,'disposition':'accepted','reason':'QC examined actual report'},expected=204)
            # Reopen actual UI after server-side classification so controls reflect real persisted state.
            suite.go(r1,'/moderation/reports','app-admin-reports-page',base);p.locator('.status-tabs button').nth(1).click();p.locator('input.report-search').fill(title)
            p.locator('tbody tr').filter(has_text=title).locator('.btn-resolve').click()
            stage=p.locator('.case-resolution');stage.locator('select').select_option(decision);stage.locator('textarea').fill('QC '+decision+' with reason')
            suite.response(r1,path+'/resolve',lambda:stage.locator('.modal-footer .btn-primary').click(),method='POST')
            final=suite.api(r1,'get',path).json();assert final['case']['status']==('escalated' if decision=='escalate' else 'resolved')
            suite.api(r1,'post',path+'/resolve',data={'decision':decision,'reason':'QC processed replay'},expected=(400,409))
            managed=suite.api(owner,'get','/videos/manage',params={'channelId':video['channelId'],'page':1,'pageSize':100}).json()['items']
            state=next(v for v in managed if v['videoId']==vid)
            if decision=='age_restrict':assert state['ageRestricted']
            if decision=='recommendation_restricted':assert vid not in feed_ids(),'Restricted target still appears in real discovery feed'
            if decision in ('hide','remove'):suite.api(member,'get','/videos/'+vid+'/playback',expected=(403,404,409))
            else:suite.api(owner,'get','/videos/'+vid+'/playback')
            entry['resource_ids']=[vid,case_id];entry['steps']=['Reviewer1 UI claims exact report case','Reviewer2 cannot claim or decide foreign case','Unclassified resolution rejected','Real classification persists; UI decision with reason','Cross-actor target effect verified','Terminal replay denied']
            entry['mail_manual']='NOT_EXECUTED; notification state is tested separately'
        case(suite,r1,'REPORT-DECISION-'+decision.upper(),'A-MODERATION.03','Classified report decision '+decision,resolve,'reports')
